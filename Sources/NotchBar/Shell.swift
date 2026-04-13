import Foundation

/// Result of a shell command execution.
struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    /// True if the process launched and exited with code 0.
    var succeeded: Bool { exitCode == 0 }

    /// Non-empty stdout, or nil. Useful for optional chaining like the old API.
    var output: String? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : stdout
    }
}

/// Lightweight wrapper for running shell commands synchronously.
enum Shell {
    /// Run an executable with arguments and return a typed ShellResult.
    /// Returns nil only if the process fails to launch at all.
    ///
    /// Both stdout and stderr are read concurrently to avoid pipe-buffer
    /// deadlocks: if a child writes more than the pipe buffer size (~64KB) to
    /// one stream while we're blocked reading the other, the child would stall
    /// waiting for buffer space, and we'd hang forever.
    static func execute(_ executable: String, _ args: [String], cwd: String? = nil) -> ShellResult? {
        // Validate executable exists before trying to launch (avoids noisy ObjC exceptions)
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }

        let outPipe = Pipe()
        let errPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read both pipes concurrently to prevent deadlock on large output streams.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let readQueue = DispatchQueue(label: "com.notchbar.shell.read", attributes: .concurrent)

        group.enter()
        readQueue.async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        readQueue.async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        // Wait for pipe readers to finish draining (they exit once the child
        // closes its fds, which happens on exit).
        group.wait()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Convenience: run and return stdout as optional String (nil if launch failed or empty output).
    /// Preserves the old API for callers that don't need exit code / stderr.
    static func run(_ executable: String, _ args: [String], cwd: String? = nil) -> String? {
        execute(executable, args, cwd: cwd)?.output
    }

    /// Run pgrep -x for an exact process name match. Returns matching PIDs.
    static func pgrep(_ processName: String) -> [Int32] {
        guard let output = run("/usr/bin/pgrep", ["-x", processName]) else { return [] }
        return output
            .components(separatedBy: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
    }

    /// Get the current working directory for a PID via lsof.
    static func cwd(for pid: Int32) -> String? {
        guard let output = run("/usr/sbin/lsof", ["-p", String(pid), "-Fn", "-d", "cwd"]) else { return nil }
        guard let line = output.components(separatedBy: "\n").first(where: { $0.hasPrefix("n/") }) else { return nil }
        return String(line.dropFirst())
    }

    /// Walk the parent process chain to check if a PID is running under a known terminal emulator.
    static func isRunningInTerminal(pid: Int32) -> Bool {
        let knownTerminals = ["Terminal", "iTerm", "Warp", "Alacritty", "kitty", "WezTerm"]
        var currentPid = pid
        for _ in 0..<10 {
            guard let output = run("/bin/ps", ["-p", String(currentPid), "-o", "ppid=,comm="])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { return false }
            let parts = output.split(separator: " ", maxSplits: 1)
            guard parts.count >= 2 else { return false }
            let comm = String(parts[1])
            if knownTerminals.contains(where: { comm.contains($0) }) { return true }
            guard let ppid = Int32(parts[0].trimmingCharacters(in: .whitespaces)), ppid > 1 else { return false }
            currentPid = ppid
        }
        return false
    }

    /// Read the first non-empty file from a list of candidate paths (background thread).
    /// Calls `onFound` on the main thread with the content.
    static func readFirstExisting(_ paths: [String], onFound: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            for path in paths {
                if let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
                    DispatchQueue.main.async { onFound(content) }
                    return
                }
            }
        }
    }

    /// Parse JSONL lines, splitting on newlines and buffering partials.
    /// Returns parsed JSON dictionaries and updates the partial line buffer.
    static func parseJSONLines(text: String, partialLine: inout String) -> [[String: Any]] {
        let fullText = partialLine + text
        var lines = fullText.components(separatedBy: "\n")
        partialLine = fullText.hasSuffix("\n") || lines.isEmpty ? "" : lines.removeLast()
        return lines.compactMap { line in
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json
        }
    }

    /// Read incremental data from a file starting at `offset`.
    /// Returns the decoded text and the new file offset, or nil on failure.
    static func readTail(path: String, from offset: UInt64) -> (text: String, newOffset: UInt64)? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        // offset + data.count avoids another syscall and never disagrees with
        // the number of bytes we just consumed (unlike offsetInFile, which can
        // be affected by concurrent truncation).
        return (text, offset + UInt64(data.count))
    }
}
