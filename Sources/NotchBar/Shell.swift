import Foundation

/// Lightweight wrapper for running shell commands synchronously.
enum Shell {
    /// Run an executable with arguments and return stdout as a String.
    /// Returns nil if the process fails to launch or produces no output.
    static func run(_ executable: String, _ args: [String], cwd: String? = nil) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
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
        defer { handle.closeFile() }
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        return (text, handle.offsetInFile)
    }
}
