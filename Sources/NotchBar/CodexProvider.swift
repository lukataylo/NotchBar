import Foundation
import AppKit
import os.log
import ApplicationServices

private let codexLog = Logger(subsystem: "com.notchbar", category: "codex")

final class CodexProvider: AgentProviderController {
    let descriptor = ProviderCatalog.codex

    private let state: NotchState
    private var pollTimer: Timer?
    private var sessionLifecycleTimer: Timer?
    private var knownSessionFiles: [String: URL] = [:]
    private let managedProfileStart = "# BEGIN NOTCHBAR CODEX PROFILE"
    private let managedProfileEnd = "# END NOTCHBAR CODEX PROFILE"

    init(state: NotchState) {
        self.state = state
    }

    func start() {
        detectRunningSessions()
        pollTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.transcriptPollInterval, repeats: true) { [weak self] _ in
            self?.detectRunningSessions()
            self?.pollSessions()
        }
        sessionLifecycleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSessionLifecycle()
        }
    }

    func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
        sessionLifecycleTimer?.invalidate()
        sessionLifecycleTimer = nil
    }

    func sendInput(_ message: String, for session: AgentSession?) {
        sendToTerminal(message, processName: descriptor.executableName)
        guard let session else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if session.tasks.count >= 10 { session.tasks.removeFirst() }
            session.tasks.append(TaskItem(title: "You: \(String(message.prefix(50)))", status: .completed))
            self.state.objectWillChange.send()
        }
    }

    func sendQuickCommand(_ command: String, for session: AgentSession?) {
        sendInput(command, for: session)
    }

    func listPastSessions() -> [PastSession] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let files = try? allSessionFiles(in: root) else { return [] }

        return files.compactMap { url in
            let sessionID = Self.sessionID(from: url.lastPathComponent)
            let metadata = CodexTranscriptReader.readSessionMetadata(from: url.path)
            guard let metadata else { return nil }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return PastSession(
                id: sessionID ?? url.deletingPathExtension().lastPathComponent,
                providerID: .codex,
                projectPath: metadata.cwd,
                projectName: (metadata.cwd as NSString).lastPathComponent,
                lastModified: modDate
            )
        }
        .sorted { $0.lastModified > $1.lastModified }
    }

    func resumeSession(_ session: PastSession) {
        let profileFlag = hasInstalledManagedProfile() ? "-p notchbar " : ""
        let command = "cd \\\"\(session.projectPath)\\\" && codex \(profileFlag)resume \(session.id)"
        runInTerminal(command)
    }

    func installIntegration() -> Bool {
        let url = codexConfigURL()
        let block = """
\(managedProfileStart)
[profiles.notchbar]
approval_policy = "on-request"
sandbox_mode = "workspace-write"
model_reasoning_effort = "medium"
\(managedProfileEnd)
"""

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let stripped = stripManagedProfile(from: existing)
            let separator = stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            let updated = stripped.trimmingCharacters(in: .whitespacesAndNewlines) + separator + block + "\n"
            try updated.write(to: url, atomically: true, encoding: .utf8)
            codexLog.info("Installed NotchBar Codex profile at \(url.path)")
            return true
        } catch {
            codexLog.error("Failed to install Codex profile: \(error.localizedDescription)")
            return false
        }
    }

    func removeIntegration() -> Bool {
        let url = codexConfigURL()
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = stripManagedProfile(from: existing).trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if updated.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try "".write(to: url, atomically: true, encoding: .utf8)
                }
            } else {
                try (updated + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            codexLog.info("Removed NotchBar Codex profile from \(url.path)")
            return true
        } catch {
            codexLog.error("Failed to remove Codex profile: \(error.localizedDescription)")
            return false
        }
    }

    private func detectRunningSessions() {
        let pipe = Pipe()
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", descriptor.executableName]
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice

        guard (try? pgrep.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return }

        let pids = output
            .components(separatedBy: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }

        guard !pids.isEmpty else { return }

        let latestByPath = latestSessionFilesByProjectPath()
        for pid in pids {
            guard let cwd = currentWorkingDirectory(for: pid) else { continue }
            let projectName = (cwd as NSString).lastPathComponent
            let session = existingSession(for: cwd) ?? AgentSession(name: projectName, projectPath: cwd, providerID: .codex)

            if existingSession(for: cwd) == nil {
                session.isActive = true
                session.statusMessage = "Connected"
                session.startedAt = Date()
                session.pid = pid
                state.sessions.append(session)
            }

            session.pid = pid
            session.isActive = true
            session.isCompleted = false
            session.terminalAvailable = Self.isRunningInTerminal(pid: pid)

            if session.instructionsContent == nil {
                readInstructions(for: session)
            }

            if let sessionFile = latestByPath[cwd] {
                knownSessionFiles[cwd] = sessionFile
                if session.transcriptPath != sessionFile.path {
                    session.transcriptPath = sessionFile.path
                    session.transcriptReader = CodexTranscriptReader(path: sessionFile.path)
                }
            }
        }

        if !state.sessions.isEmpty && state.activeSession == nil {
            state.activeSessionIndex = 0
        }
    }

    private func pollSessions() {
        var changed = false

        for session in state.sessions where session.providerID == .codex {
            if let file = knownSessionFiles[session.projectPath], session.transcriptReader == nil {
                session.transcriptPath = file.path
                session.transcriptReader = CodexTranscriptReader(path: file.path)
            }

            guard let reader = session.transcriptReader else { continue }
            let entries = reader.readNew()

            for entry in entries {
                switch entry {
                case .reasoning(let text):
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        session.lastReasoning = String(clean.prefix(180))
                        session.statusMessage = "Thinking"
                        session.isWaitingForUser = false
                        changed = true
                    }
                case .usage(let input, let output):
                    session.inputTokens = input
                    session.outputTokens = output
                    session.updateCost()
                    changed = true
                case .userMessage:
                    session.isWaitingForUser = false
                    session.isActive = true
                    session.isCompleted = false
                    changed = true
                case .modelInfo(let model):
                    session.modelName = model
                    session.updateCost()
                    changed = true
                case .status(let status):
                    session.statusMessage = status
                    changed = true
                case .response(let text):
                    session.lastResponse = text
                    session.progress = min(session.progress + 0.08, 0.95)
                    changed = true
                case .turnStarted:
                    session.isActive = true
                    session.isCompleted = false
                    session.isWaitingForUser = false
                    session.progress = max(session.progress, 0.05)
                    session.statusMessage = "Working"
                    changed = true
                case .waitingForInput:
                    session.isWaitingForUser = true
                    session.progress = min(max(session.progress, 0.9), 0.95)
                    session.statusMessage = "Waiting for input"
                    changed = true
                case .taskStarted(let event):
                    session.isActive = true
                    session.isCompleted = false
                    session.isWaitingForUser = false
                    session.statusMessage = event.title
                    if let index = session.tasks.lastIndex(where: { $0.requestId == event.id }) {
                        session.tasks[index].status = .running
                        session.tasks[index].detail = event.detail
                    } else {
                        if session.tasks.count >= 12 { session.tasks.removeFirst() }
                        session.tasks.append(TaskItem(
                            title: event.title,
                            status: .running,
                            detail: event.detail,
                            toolName: event.toolName,
                            filePath: event.filePath,
                            requestId: event.id
                        ))
                    }
                    changed = true
                case .taskCompleted(let event):
                    session.isActive = true
                    session.isWaitingForUser = false
                    if let index = session.tasks.lastIndex(where: { $0.requestId == event.id }) {
                        session.tasks[index].status = .completed
                        session.tasks[index].detail = event.detail
                    } else {
                        if session.tasks.count >= 12 { session.tasks.removeFirst() }
                        session.tasks.append(TaskItem(
                            title: event.title,
                            status: .completed,
                            detail: event.detail,
                            toolName: event.toolName,
                            filePath: event.filePath,
                            requestId: event.id
                        ))
                    }
                    session.progress = min(session.progress + 0.1, 0.88)
                    changed = true
                case .sessionCompleted:
                    session.isCompleted = true
                    session.isActive = false
                    session.progress = 1.0
                    session.statusMessage = "Completed"
                    session.isWaitingForUser = false
                    changed = true
                }
            }
        }

        if changed {
            state.objectWillChange.send()
        }
    }

    private func existingSession(for projectPath: String) -> AgentSession? {
        state.sessions.first { $0.projectPath == projectPath && $0.providerID == .codex }
    }

    private func checkSessionLifecycle() {
        let activePids = currentCodexPIDs()
        for session in state.sessions where session.providerID == .codex && session.isActive {
            if let pid = session.pid, !activePids.contains(pid) {
                session.isCompleted = true
                session.isActive = false
                session.isWaitingForUser = false
                session.progress = 1.0
                session.statusMessage = "Completed"
            }
        }
        state.objectWillChange.send()
    }

    private func latestSessionFilesByProjectPath() -> [String: URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let files = try? allSessionFiles(in: root) else { return [:] }

        var map: [String: (url: URL, date: Date)] = [:]
        for url in files {
            guard let metadata = CodexTranscriptReader.readSessionMetadata(from: url.path) else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let existing = map[metadata.cwd], existing.date >= modDate {
                continue
            }
            map[metadata.cwd] = (url, modDate)
        }

        return map.mapValues(\.url)
    }

    private func allSessionFiles(in root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        var files: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            files.append(item)
        }
        return files
    }

    private func readInstructions(for session: AgentSession) {
        let paths = [
            session.projectPath + "/AGENTS.md",
            session.projectPath + "/.codex/AGENTS.md",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/AGENTS.md").path
        ]

        DispatchQueue.global(qos: .utility).async {
            for path in paths {
                if let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
                    DispatchQueue.main.async {
                        session.instructionsContent = content
                    }
                    return
                }
            }
        }
    }

    private func currentWorkingDirectory(for pid: Int32) -> String? {
        let pipe = Pipe()
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-p", String(pid), "-Fn", "-d", "cwd"]
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice

        guard (try? lsof.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        guard let line = output.components(separatedBy: "\n").last(where: { $0.hasPrefix("n/") }) else { return nil }
        return String(line.dropFirst())
    }

    private func currentCodexPIDs() -> Set<Int32> {
        let pipe = Pipe()
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", descriptor.executableName]
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return Set(
            output
                .components(separatedBy: "\n")
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { $0 > 0 }
        )
    }

    private func codexConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    private func hasInstalledManagedProfile() -> Bool {
        guard let text = try? String(contentsOf: codexConfigURL(), encoding: .utf8) else { return false }
        return text.contains(managedProfileStart) && text.contains(managedProfileEnd)
    }

    private func stripManagedProfile(from text: String) -> String {
        let pattern = "\(NSRegularExpression.escapedPattern(for: managedProfileStart))[\\s\\S]*?\(NSRegularExpression.escapedPattern(for: managedProfileEnd))\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func sessionID(from filename: String) -> String? {
        guard let range = filename.range(of: "[0-9a-f]{8,}-[0-9a-f-]+", options: .regularExpression) else {
            return nil
        }
        return String(filename[range])
    }

    private static func isRunningInTerminal(pid: Int32) -> Bool {
        var currentPid = pid
        for _ in 0..<10 {
            let pipe = Pipe()
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-p", String(currentPid), "-o", "ppid=,comm="]
            ps.standardOutput = pipe
            ps.standardError = FileHandle.nullDevice
            guard (try? ps.run()) != nil else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            ps.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { return false }
            let parts = output.split(separator: " ", maxSplits: 1)
            guard parts.count >= 2 else { return false }
            let comm = String(parts[1])
            if comm.contains("Terminal") || comm.contains("iTerm") { return true }
            guard let ppid = Int32(parts[0].trimmingCharacters(in: .whitespaces)), ppid > 1 else { return false }
            currentPid = ppid
        }
        return false
    }

    private func sendToTerminal(_ message: String, processName: String) {
        guard AXIsProcessTrusted() else {
            codexLog.warning("Accessibility permission not granted")
            return
        }

        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let terminalScript = """
        tell application "Terminal"
            set targetTab to missing value
            repeat with w in windows
                repeat with t in tabs of w
                    if busy of t then
                        if processes of t contains "\(processName)" then
                            set targetTab to t
                            set frontmost of w to true
                            exit repeat
                        end if
                    end if
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat
            if targetTab is not missing value then
                tell application "System Events" to tell process "Terminal"
                    keystroke "\(escaped)"
                    keystroke return
                end tell
            end if
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: terminalScript)?.executeAndReturnError(&error)
        if error == nil { return }

        let iTermScript = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if is processing of s then
                            tell s to write text "\(escaped)"
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        NSAppleScript(source: iTermScript)?.executeAndReturnError(nil)
    }

    private func runInTerminal(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error == nil { return }

        let iTermScript = """
        tell application "iTerm2"
            activate
            tell current window
                create tab with default profile
                tell current session
                    write text "\(escaped)"
                end tell
            end tell
        end tell
        """
        NSAppleScript(source: iTermScript)?.executeAndReturnError(nil)
    }
}
