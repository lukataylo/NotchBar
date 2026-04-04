import Foundation
import os.log

private let log = Logger(subsystem: "com.notchclaude", category: "git")

struct GitIntegration {

    /// Fetch git branch and status for a session (runs on background thread)
    static func fetchStatus(for session: ClaudeSession) {
        let cwd = session.projectPath
        DispatchQueue.global(qos: .utility).async {
            let branch = runGit(["branch", "--show-current"], cwd: cwd)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = runGit(["status", "--porcelain"], cwd: cwd)
            let changedFiles = status?.components(separatedBy: "\n").filter { !$0.isEmpty }.count ?? 0

            DispatchQueue.main.async {
                var changed = false
                if let b = branch, !b.isEmpty, session.gitBranch != b {
                    session.gitBranch = b
                    log.debug("Git branch for '\(session.name)': \(b)")
                    changed = true
                }
                if session.gitChangedFiles != changedFiles {
                    session.gitChangedFiles = changedFiles
                    changed = true
                }
                if changed {
                    session.objectWillChange.send()
                }
            }
        }
    }

    /// Fetch git diff for a specific file, returns parsed DiffFiles
    static func fetchDiff(filePath: String, cwd: String) -> [DiffFile] {
        log.debug("Fetching diff for \(filePath) in \(cwd)")
        guard let output = runGit(["diff", "--", filePath], cwd: cwd), !output.isEmpty else {
            // Try staged diff
            guard let staged = runGit(["diff", "--cached", "--", filePath], cwd: cwd), !staged.isEmpty else {
                log.debug("No diff found for \(filePath)")
                return []
            }
            let files = parseDiff(staged)
            log.debug("Parsed staged diff: \(files.count) file(s)")
            return files
        }
        let files = parseDiff(output)
        log.debug("Parsed diff: \(files.count) file(s)")
        return files
    }

    /// Parse unified diff output into DiffFile models
    static func parseDiff(_ rawDiff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentFile: String?
        var currentLines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0

        for line in rawDiff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git") {
                if let f = currentFile {
                    files.append(DiffFile(filename: f, lines: currentLines))
                }
                currentLines = []
                // Extract filename from "diff --git a/path b/path"
                let parts = line.split(separator: " ")
                if let last = parts.last, parts.count >= 4 {
                    currentFile = String(last).replacingOccurrences(of: "b/", with: "", options: .anchored)
                } else {
                    currentFile = "file"
                    log.warning("Could not parse filename from diff header: \(line)")
                }
            } else if line.hasPrefix("@@") {
                currentLines.append(DiffLine(kind: .hunkHeader, content: line, oldLineNum: nil, newLineNum: nil))
                // Parse @@ -old,count +new,count @@
                let nums = line.split(separator: " ")
                if nums.count >= 3 {
                    let oldPart = String(nums[1]).dropFirst() // remove '-'
                    let newPart = String(nums[2]).dropFirst() // remove '+'
                    oldLine = Int(oldPart.split(separator: ",").first ?? "0") ?? 0
                    newLine = Int(newPart.split(separator: ",").first ?? "0") ?? 0
                } else {
                    log.warning("Malformed hunk header, resetting line numbers: \(line)")
                    oldLine = 0
                    newLine = 0
                }
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentLines.append(DiffLine(kind: .addition, content: String(line.dropFirst()), oldLineNum: nil, newLineNum: newLine))
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentLines.append(DiffLine(kind: .deletion, content: String(line.dropFirst()), oldLineNum: oldLine, newLineNum: nil))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                currentLines.append(DiffLine(kind: .context, content: String(line.dropFirst()), oldLineNum: oldLine, newLineNum: newLine))
                oldLine += 1
                newLine += 1
            }
        }

        if let f = currentFile {
            files.append(DiffFile(filename: f, lines: currentLines))
        }
        return files
    }

    // MARK: - Private

    private static func runGit(_ args: [String], cwd: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("Failed to run git \(args.joined(separator: " ")) in \(cwd): \(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            log.debug("git \(args.joined(separator: " ")) exited with status \(process.terminationStatus)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
