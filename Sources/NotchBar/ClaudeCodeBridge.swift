import Foundation
import AppKit
import os.log
import UserNotifications

private let log = Logger(subsystem: "com.notchclaude", category: "bridge")

// MARK: - Claude Code Hook Event

struct ClaudeCodeEvent: Codable {
    let sessionId: String?
    let cwd: String?
    let permissionMode: String?
    let hookEventName: String?
    let toolName: String?
    let toolInput: [String: AnyCodableValue]?
    let toolResponse: ToolResponse?
    let toolUseId: String?
    let hookType: String?
    let requestId: String?
    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", cwd, permissionMode = "permission_mode"
        case hookEventName = "hook_event_name", toolName = "tool_name"
        case toolInput = "tool_input", toolResponse = "tool_response"
        case toolUseId = "tool_use_id", hookType = "hook_type", requestId = "request_id"
        case transcriptPath = "transcript_path"
    }

    struct ToolResponse: Codable {
        let stdout: String?
        let stderr: String?
        let interrupted: Bool?
    }

    var toolDescription: String {
        guard let input = toolInput else { return toolName ?? "Tool" }
        switch toolName {
        case "Edit": return "Edit \(shortPath(input["file_path"]?.stringValue))"
        case "Write": return "Write \(shortPath(input["file_path"]?.stringValue))"
        case "Read": return "Read \(shortPath(input["file_path"]?.stringValue))"
        case "Bash":
            return input["description"]?.stringValue ?? "Run: \(String((input["command"]?.stringValue ?? "").prefix(50)))"
        case "Glob": return "Search: \(input["pattern"]?.stringValue ?? "")"
        case "Grep": return "Grep: \(input["pattern"]?.stringValue ?? "")"
        case "Agent": return "Agent: \(input["description"]?.stringValue ?? "subagent")"
        default: return toolName ?? "Tool"
        }
    }

    var isWriteOperation: Bool { ["Edit", "Write", "Bash", "NotebookEdit"].contains(toolName) }

    var filePath: String? { toolInput?["file_path"]?.stringValue }
    var bashCommand: String? { toolInput?["command"]?.stringValue }

    private func shortPath(_ path: String?) -> String {
        guard let path = path else { return "file" }
        let parts = path.split(separator: "/")
        return parts.count > 2 ? String(parts.suffix(2).joined(separator: "/")) : path
    }
}

// MARK: - AnyCodableValue

enum AnyCodableValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else { self = .null }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
}

// MARK: - Bridge

class ClaudeCodeBridge: AgentProviderController {
    static var shared: ClaudeCodeBridge?
    let descriptor = ProviderCatalog.claude

    let eventsDir: URL
    let responsesDir: URL
    let binDir: URL
    let state: NotchState
    var source: DispatchSourceFileSystemObject?
    var dirFD: Int32 = -1

    var sessionMap: [String: UUID] = [:]
    var toolCounts: [String: Int] = [:]
    var runningTools: [String: (sessionUUID: UUID, taskTitle: String)] = [:]
    var transcriptTimer: Timer?
    var sessionLifecycleTimer: Timer?
    var gitTimer: Timer?
    var handledEvents: Set<String> = []
    var approvalTimers: [String: Timer] = [:]

    init(state: NotchState) {
        self.state = state
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchclaude")
        eventsDir = base.appendingPathComponent("events")
        responsesDir = base.appendingPathComponent("responses")
        binDir = base.appendingPathComponent("bin")
        Self.shared = self
    }

    func start() {
        log.info("Bridge initializing...")
        log.info("Events dir: \(self.eventsDir.path)")
        log.info("Responses dir: \(self.responsesDir.path)")
        log.info("Bin dir: \(self.binDir.path)")
        let fm = FileManager.default
        try? fm.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        writeHookScript()
        log.info("Hook script written")
        requestNotificationPermission()

        dirFD = open(eventsDir.path, O_EVTONLY)
        guard dirFD >= 0 else { log.error("Failed to open events dir at \(self.eventsDir.path)"); return }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: .write, queue: .main)
        guard source != nil else {
            log.error("Failed to create DispatchSource for events dir")
            close(dirFD)
            dirFD = -1
            return
        }
        source?.setEventHandler { [weak self] in self?.processEvents() }
        source?.setCancelHandler { [weak self] in if let fd = self?.dirFD, fd >= 0 { close(fd) } }
        source?.resume()
        log.info("Bridge started, watching \(self.eventsDir.path)")

        transcriptTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.transcriptPollInterval, repeats: true) { [weak self] _ in
            self?.pollTranscripts()
        }

        // Session lifecycle: detect when claude processes exit
        sessionLifecycleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSessionLifecycle()
        }

        // Git status polling
        gitTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.pollGitStatus()
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.detectRunningSessions()
        }
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { log.info("Notification permission granted") }
        }
    }

    func sendNotification(title: String, body: String, sound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Session Detection

    private func detectRunningSessions() {
        // Use pgrep -x for exact process name matching (avoids false positives)
        let pipe = Pipe()
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "claude"]
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return }

        var pids: [Int32] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(trimmed), pid > 0 { pids.append(pid) }
        }
        guard !pids.isEmpty else {
            log.info("No running claude processes found")
            return
        }
        log.info("Found \(pids.count) claude process(es): \(pids.map(String.init).joined(separator: ", "))")

        var sessions: [(name: String, path: String, pid: Int32)] = []
        for pid in pids {
            let lp = Pipe()
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-p", String(pid), "-Fn", "-d", "cwd"]
            lsof.standardOutput = lp
            lsof.standardError = FileHandle.nullDevice
            guard (try? lsof.run()) != nil else { continue }
            let ld = lp.fileHandleForReading.readDataToEndOfFile()
            lsof.waitUntilExit()
            if let out = String(data: ld, encoding: .utf8),
               let line = out.components(separatedBy: "\n").last(where: { $0.hasPrefix("n/") }) {
                let cwd = String(line.dropFirst())
                let name = (cwd as NSString).lastPathComponent
                sessions.append((name: name, path: cwd, pid: pid))
            }
        }

        guard !sessions.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for s in sessions {
                if self.state.sessions.contains(where: { $0.projectPath == s.path && !$0.isCompleted }) { continue }
                let session = AgentSession(name: s.name, projectPath: s.path, providerID: .claude)
                session.isActive = true
                session.statusMessage = "Running"
                session.pid = s.pid
                self.state.sessions.append(session)
                self.readClaudeMd(for: session)
                self.detectTerminal(for: session)
            }
            if self.state.sessions.count > 0 { self.state.activeSessionIndex = 0 }
            self.state.objectWillChange.send()
        }
    }

    // MARK: - Terminal Detection

    /// Check if a claude process is running under Terminal.app or iTerm2
    /// by walking the parent process chain
    func detectTerminal(for session: ClaudeSession) {
        guard let pid = session.pid else { return }
        DispatchQueue.global(qos: .utility).async {
            let available = Self.isRunningInTerminal(pid: pid)
            DispatchQueue.main.async {
                session.terminalAvailable = available
                log.info("Terminal available for '\(session.name)': \(available)")
            }
        }
    }

    private static func isRunningInTerminal(pid: Int32) -> Bool {
        // Walk parent PIDs and check if any are Terminal or iTerm2
        var currentPid = pid
        for _ in 0..<10 {  // max depth to avoid loops
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
        // Also just check if Terminal.app or iTerm2 is running at all
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.bundleIdentifier == "com.apple.Terminal" || $0.bundleIdentifier == "com.googlecode.iterm2" }
    }

    // MARK: - Session Lifecycle

    private func checkSessionLifecycle() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let pipe = Pipe()
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-x", "claude"]
            pgrep.standardOutput = pipe
            pgrep.standardError = FileHandle.nullDevice
            guard (try? pgrep.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pgrep.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return }

            var activePids = Set<Int32>()
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let pid = Int32(trimmed), pid > 0 { activePids.insert(pid) }
            }

            DispatchQueue.main.async {
                var changed = false
                for session in self.state.sessions where session.providerID == .claude && session.isActive && !session.isCompleted {
                    if let pid = session.pid, !activePids.contains(pid) {
                        log.info("Session '\(session.name)' (pid \(pid)) completed - process no longer running")
                        session.isCompleted = true
                        session.isActive = false
                        session.statusMessage = "Completed"
                        session.progress = 1.0
                        changed = true
                        if AppSettings.shared.notifySessionComplete {
                            self.sendNotification(title: "Session Complete", body: "\(session.name) finished. \(session.tokenSummary) \(session.costSummary)")
                        }
                    }
                }
                if changed { self.state.objectWillChange.send() }
            }
        }
    }

    // MARK: - CLAUDE.md Reader

    func readClaudeMd(for session: AgentSession) {
        DispatchQueue.global(qos: .utility).async {
            let paths = [
                session.projectPath + "/CLAUDE.md",
                session.projectPath + "/.claude/CLAUDE.md"
            ]
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

    // MARK: - Git Status Polling

    private func pollGitStatus() {
        for session in state.sessions where session.isActive && !session.isCompleted {
            GitIntegration.fetchStatus(for: session)
        }
    }

    // MARK: - Process Events

    func processEvents() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil) else { return }

        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let filename = file.lastPathComponent

            if handledEvents.contains(filename) { continue }

            var data: Data
            do {
                data = try Data(contentsOf: file)
            } catch {
                log.error("Failed to read event file \(filename): \(error.localizedDescription)")
                continue
            }

            var event: ClaudeCodeEvent
            do {
                event = try JSONDecoder().decode(ClaudeCodeEvent.self, from: data)
            } catch {
                log.error("Failed to decode event file \(filename): \(error.localizedDescription)")
                if let a = try? fm.attributesOfItem(atPath: file.path),
                   let d = a[.creationDate] as? Date, Date().timeIntervalSince(d) > 10 {
                    try? fm.removeItem(at: file)
                }
                continue
            }

            handledEvents.insert(filename)
            handleEvent(event)
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Handle Event

    func handleEvent(_ event: ClaudeCodeEvent) {
        guard let sessionId = event.sessionId else {
            log.warning("Received event with no sessionId, ignoring")
            return
        }
        log.info("Event: \(event.hookType ?? event.hookEventName ?? "unknown") tool=\(event.toolName ?? "nil") session=\(String(sessionId.prefix(8)))")

        let projectName = event.cwd.map { ($0 as NSString).lastPathComponent } ?? String(sessionId.prefix(8))
        let session: ClaudeSession
        if let uuid = sessionMap[sessionId], let existing = state.sessions.first(where: { $0.id == uuid }) {
            session = existing
        } else {
            let s = AgentSession(name: projectName, projectPath: event.cwd ?? "~", providerID: .claude)
            s.isActive = true; s.statusMessage = "Connected"
            state.sessions.append(s)
            sessionMap[sessionId] = s.id
            toolCounts[sessionId] = 0
            session = s
            if state.sessions.count == 1 { state.activeSessionIndex = 0 }
            readClaudeMd(for: s)
            detectTerminal(for: s)
        }

        // Update permission mode from event
        if let mode = event.permissionMode {
            session.permissionMode = mode
        }

        // Set up transcript reader if we have the path
        if let tp = event.transcriptPath, session.transcriptReader == nil {
            session.transcriptPath = tp
            session.transcriptReader = TranscriptReader(path: tp)
        }

        let hookType = event.hookType ?? event.hookEventName?.lowercased() ?? ""
        let toolUseId = event.toolUseId ?? event.requestId ?? UUID().uuidString

        switch hookType {
        case "pre-tool-use", "pretooluse":
            let desc = event.toolDescription
            let toolName = event.toolName ?? "Tool"
            let settings = AppSettings.shared

            if session.tasks.count >= 10 { session.tasks.removeFirst() }

            // Check if this tool needs approval
            let needsApproval = !settings.shouldAutoApprove(toolName: toolName)

            if needsApproval {
                log.info("Tool '\(toolName)' requires approval (request: \(toolUseId))")
                // Create pending approval
                let approval = PendingApproval(
                    requestId: toolUseId,
                    toolName: toolName,
                    toolDescription: desc,
                    filePath: event.filePath,
                    bashCommand: event.bashCommand,
                    isWriteOperation: event.isWriteOperation
                )
                session.pendingApproval = approval
                session.tasks.append(TaskItem(title: desc, status: .pendingApproval, toolName: toolName, filePath: event.filePath))
                session.statusMessage = "Awaiting approval: \(desc)"

                // Auto-expand the panel
                if state.expandedScreenID == nil {
                    let loc = NSEvent.mouseLocation
                    state.expandedScreenID = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.displayID
                }

                if settings.notifyApprovalNeeded {
                    sendNotification(title: "Approval Needed", body: desc)
                }
                settings.playSound("Submarine")

                // Set timeout timer
                let timeoutMinutes = settings.approvalTimeoutMinutes
                if timeoutMinutes > 0 {
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutMinutes * 60), repeats: false) { [weak self] _ in
                        self?.approveAction(requestId: toolUseId, sessionId: session.id)
                    }
                    approvalTimers[toolUseId] = timer
                }
            } else {
                log.info("Tool '\(toolName)' auto-approved by settings (request: \(toolUseId))")
                session.tasks.append(TaskItem(title: desc, status: .running, toolName: toolName, filePath: event.filePath))
                session.statusMessage = desc
                // Write immediate approve response so hook script unblocks
                writeApprovalResponse(requestId: toolUseId, decision: "approve")
            }

            session.isWaitingForUser = false
            runningTools[toolUseId] = (sessionUUID: session.id, taskTitle: desc)

        case "post-tool-use", "posttooluse":
            let desc = event.toolDescription
            toolCounts[sessionId, default: 0] += 1

            let detail: String?
            if let r = event.toolResponse {
                detail = r.interrupted == true ? "interrupted" : (r.stderr?.isEmpty == false ? "stderr" : nil)
                if let stdout = r.stdout, !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lines = trimmed.components(separatedBy: "\n").suffix(4)
                    session.lastResponse = String(lines.joined(separator: "\n").suffix(200))
                }
            } else { detail = nil }

            if let info = runningTools.removeValue(forKey: toolUseId),
               let idx = session.tasks.lastIndex(where: { $0.title == info.taskTitle && ($0.status == .running || $0.status == .pendingApproval) }) {
                session.tasks[idx].status = .completed
                session.tasks[idx].detail = detail
            } else {
                if session.tasks.count >= 10 { session.tasks.removeFirst() }
                session.tasks.append(TaskItem(title: desc, status: .completed, detail: detail, toolName: event.toolName, filePath: event.filePath))
            }

            // Clear pending approval if this was it
            if session.pendingApproval?.requestId == toolUseId {
                session.pendingApproval = nil
            }

            // Fetch diff for write operations
            if event.isWriteOperation, let fp = event.filePath {
                fetchDiffForTask(filePath: fp, cwd: session.projectPath, session: session, toolUseId: toolUseId)
            }

            let count = toolCounts[sessionId, default: 1]
            session.progress = min(1.0 - 1.0 / (Double(count) * 0.3 + 1.0), 0.95)
            session.statusMessage = desc

        default: break
        }
        state.objectWillChange.send()
    }

    // MARK: - Approval Actions

    func approveAction(requestId: String, sessionId: UUID) {
        log.info("Approving request \(requestId)")
        writeApprovalResponse(requestId: requestId, decision: "approve")
        approvalTimers[requestId]?.invalidate()
        approvalTimers.removeValue(forKey: requestId)

        if let session = state.sessions.first(where: { $0.id == sessionId }) {
            if session.pendingApproval?.requestId == requestId {
                session.pendingApproval = nil
                if let idx = session.tasks.lastIndex(where: { $0.status == .pendingApproval }) {
                    session.tasks[idx].status = .running
                }
                session.statusMessage = "Approved"
            }
            state.objectWillChange.send()
        }
    }

    func rejectAction(requestId: String, sessionId: UUID) {
        log.info("Rejecting request \(requestId)")
        writeApprovalResponse(requestId: requestId, decision: "deny", reason: "User rejected from NotchClaude")
        approvalTimers[requestId]?.invalidate()
        approvalTimers.removeValue(forKey: requestId)

        if let session = state.sessions.first(where: { $0.id == sessionId }) {
            if session.pendingApproval?.requestId == requestId {
                session.pendingApproval = nil
                if let idx = session.tasks.lastIndex(where: { $0.status == .pendingApproval }) {
                    session.tasks[idx].status = .rejected
                }
                session.statusMessage = "Rejected"
            }
            state.objectWillChange.send()
        }
    }

    private func writeApprovalResponse(requestId: String, decision: String, reason: String? = nil) {
        var response: [String: Any] = ["decision": decision]
        if let reason = reason { response["reason"] = reason }
        do {
            let data = try JSONSerialization.data(withJSONObject: response)
            let url = responsesDir.appendingPathComponent("\(requestId).json")
            try data.write(to: url, options: .atomic)
            log.info("Wrote approval response: \(decision) for \(requestId)")
        } catch {
            log.error("Failed to write approval response for \(requestId): \(error.localizedDescription)")
        }
    }

    // MARK: - Diff Fetching

    private func fetchDiffForTask(filePath: String, cwd: String, session: ClaudeSession, toolUseId: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let diffs = GitIntegration.fetchDiff(filePath: filePath, cwd: cwd)
            guard !diffs.isEmpty else { return }
            DispatchQueue.main.async {
                if let idx = session.tasks.lastIndex(where: { $0.filePath == filePath && $0.status == .completed }) {
                    session.tasks[idx].diffFiles = diffs
                }
                self?.state.objectWillChange.send()
            }
        }
    }

    // MARK: - Transcript Polling

    func pollTranscripts() {
        var changed = false
        for session in state.sessions where session.providerID == .claude && session.isActive {
            guard let reader = session.transcriptReader else { continue }
            let entries = reader.readNew()
            for entry in entries {
                switch entry {
                case .reasoning(let text):
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        let summary: String
                        if let dotIdx = clean.firstIndex(of: "."), clean.distance(from: clean.startIndex, to: dotIdx) < 150 {
                            summary = String(clean[...dotIdx])
                        } else {
                            summary = String(clean.prefix(150))
                        }
                        session.lastReasoning = summary
                        changed = true
                    }
                case .usage(let input, let output):
                    session.inputTokens = input
                    session.outputTokens = output
                    session.updateCost()
                    changed = true

                    // Cost alert
                    let threshold = AppSettings.shared.costAlertThreshold
                    if session.estimatedCost >= threshold && (session.estimatedCost - ModelPricing.estimate(provider: session.providerID, model: session.modelName, inputTokens: input, outputTokens: 0)) < threshold {
                        sendNotification(title: "Cost Alert", body: "\(session.name) has exceeded \(String(format: "$%.2f", threshold))")
                    }
                case .userMessage:
                    session.isWaitingForUser = false
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
                    changed = true
                case .turnStarted, .waitingForInput, .taskStarted, .taskCompleted:
                    break
                case .sessionCompleted:
                    session.isCompleted = true
                    session.isActive = false
                    session.progress = 1.0
                    changed = true
                }
            }
        }
        if changed { state.objectWillChange.send() }
    }

    func sendInput(_ message: String, for session: AgentSession?) {
        sendToTerminal(message)
    }

    func sendQuickCommand(_ command: String, for session: AgentSession?) {
        sendSlashCommand(command)
    }

    func installIntegration() -> Bool {
        installHooks()
    }

    func removeIntegration() -> Bool {
        removeHooks()
    }

    func listPastSessions() -> [PastSession] {
        SessionHistoryManager.shared.listPastSessions()
    }

    func resumeSession(_ session: PastSession) {
        SessionHistoryManager.shared.resumeSession(session)
    }

    // MARK: - Send Message to Terminal

    func sendToTerminal(_ message: String) {
        log.info("Sending to terminal: \(String(message.prefix(80)))")

        // Check accessibility permission (needed for keystroke injection via AppleScript)
        if !AXIsProcessTrusted() {
            log.warning("Accessibility permission not granted, prompting user")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "NotchClaude needs Accessibility access to send messages to your terminal.\n\nGo to System Settings → Privacy & Security → Accessibility and enable NotchClaude."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    // Prompt the system dialog which opens System Settings
                    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                }
            }
            return
        }

        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let termScript = """
            tell application "Terminal"
                set targetTab to missing value
                repeat with w in windows
                    repeat with t in tabs of w
                        if busy of t then
                            if processes of t contains "claude" then
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
            var err: NSDictionary?
            NSAppleScript(source: termScript)?.executeAndReturnError(&err)

            if err != nil {
                let itermScript = """
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
                NSAppleScript(source: itermScript)?.executeAndReturnError(nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let session = self?.state.activeSession else { return }
                if session.tasks.count >= 10 { session.tasks.removeFirst() }
                session.tasks.append(TaskItem(title: "You: \(String(message.prefix(50)))", status: .completed))
                self?.state.objectWillChange.send()
            }
        }
    }

    /// Send a slash command to the terminal
    func sendSlashCommand(_ command: String) {
        sendToTerminal(command)
        AppSettings.shared.playSound("Pop")
    }

    // MARK: - Cleanup

    func cleanup() {
        log.info("Bridge cleaning up...")
        // Auto-approve any pending approvals before shutting down so Claude Code isn't stuck
        for (requestId, timer) in approvalTimers {
            timer.invalidate()
            writeApprovalResponse(requestId: requestId, decision: "approve")
            log.info("Auto-approved pending request \(requestId) during shutdown")
        }
        approvalTimers.removeAll()

        if let files = try? FileManager.default.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: responsesDir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        source?.cancel()
        transcriptTimer?.invalidate()
        sessionLifecycleTimer?.invalidate()
        gitTimer?.invalidate()
        log.info("Bridge cleanup complete")
    }

    // MARK: - Hook Script

    @discardableResult
    func writeHookScript() -> Bool {
        let timeoutSeconds = AppSettings.shared.approvalTimeoutMinutes * 60
        let defaultTimeout = timeoutSeconds > 0 ? timeoutSeconds : 300

        // Pure shell — no python3 dependency
        let script = """
#!/bin/bash
# NotchClaude hook — smart approval mode
# Auto-approves reads, blocks for writes if NotchClaude is running.
# Falls back to auto-approve if NotchClaude is not running or on timeout.
EVENTS_DIR="$HOME/.notchclaude/events"
RESPONSES_DIR="$HOME/.notchclaude/responses"
LOG_FILE="$HOME/.notchclaude/hook.log"
mkdir -p "$EVENTS_DIR" "$RESPONSES_DIR"
HOOK_TYPE="${1:-notification}"
REQUEST_ID="$(date +%s)-$$-$RANDOM"
INPUT=$(cat -)

# Extract tool_name using pure shell (no python3 dependency)
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name" *: *"[^"]*"' | head -1 | sed 's/.*: *"\\([^"]*\\)".*/\\1/')

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [hook] $1" >> "$LOG_FILE" 2>/dev/null
}

log_msg "Invoked: hook_type=$HOOK_TYPE request_id=$REQUEST_ID tool=$TOOL_NAME"

# If NotchClaude is not running, auto-approve everything
if ! pgrep -x "NotchClaude" >/dev/null 2>&1; then
    log_msg "NotchClaude not running, auto-approving"
    [ "$HOOK_TYPE" = "pre-tool-use" ] && echo '{"decision":"approve"}'
    exit 0
fi

# Build event JSON: prepend hook_type and request_id to input object (pure shell)
STRIPPED=$(echo "$INPUT" | sed 's/^[[:space:]]*{//')
EVENT='{"hook_type":"'"$HOOK_TYPE"'","request_id":"'"$REQUEST_ID"'",'"$STRIPPED"
if ! echo "$EVENT" | grep -q '^{.*}$' 2>/dev/null; then
    EVENT='{"hook_type":"'"$HOOK_TYPE"'","request_id":"'"$REQUEST_ID"'"}'
fi
echo "$EVENT" > "$EVENTS_DIR/$REQUEST_ID.json"
log_msg "Event written to $EVENTS_DIR/$REQUEST_ID.json"

# For post-tool-use, no response needed
if [ "$HOOK_TYPE" != "pre-tool-use" ]; then
    log_msg "Post-tool-use, exiting"
    exit 0
fi

# Wait for NotchClaude's response (it decides whether to block based on settings)
# TIMEOUT is in seconds, we sleep 0.2s per iteration so max_iterations = TIMEOUT * 5
RESPONSE_FILE="$RESPONSES_DIR/$REQUEST_ID.json"
TIMEOUT_SECS=\(defaultTimeout)
MAX_ITERS=$((TIMEOUT_SECS * 5))
ITER=0
log_msg "Waiting for response (timeout=${TIMEOUT_SECS}s, max_iters=$MAX_ITERS)"
while [ $ITER -lt $MAX_ITERS ]; do
    if [ -f "$RESPONSE_FILE" ]; then
        RESPONSE=$(cat "$RESPONSE_FILE")
        rm -f "$RESPONSE_FILE"
        log_msg "Got response: $RESPONSE"
        echo "$RESPONSE"
        exit 0
    fi
    sleep 0.2
    ITER=$((ITER + 1))
    # Check every 25 iterations (~5s) if NotchClaude died
    if [ $((ITER % 25)) -eq 0 ] && ! pgrep -x "NotchClaude" >/dev/null 2>&1; then
        log_msg "NotchClaude died during wait, auto-approving"
        echo '{"decision":"approve"}'
        exit 0
    fi
done
# Timeout: auto-approve
log_msg "Timeout after ${TIMEOUT_SECS}s, auto-approving"
echo '{"decision":"approve"}'
"""
        let url = binDir.appendingPathComponent("notchclaude-hook")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            log.error("Failed to write hook script: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Install/Remove Hooks

    @discardableResult
    func installHooks() -> Bool {
        let hookPath = binDir.appendingPathComponent("notchclaude-hook").path
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var settings: [String: Any] = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        let notchEntry: (String) -> [String: Any] = { hookType in
            ["matcher": "", "hooks": [["type": "command", "command": "\(hookPath) \(hookType)"]]]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Merge: preserve existing hooks, remove old NotchClaude entries, add new ones
        for (key, hookType) in [("PreToolUse", "pre-tool-use"), ("PostToolUse", "post-tool-use")] {
            var entries = hooks[key] as? [[String: Any]] ?? []
            // Remove any existing notchclaude entries
            entries.removeAll { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    (h["command"] as? String)?.contains("notchclaude-hook") == true
                }
            }
            entries.append(notchEntry(hookType))
            hooks[key] = entries
        }
        settings["hooks"] = hooks

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
            try data.write(to: url)
            log.info("Hooks installed successfully (existing hooks preserved)")
            return true
        } catch {
            log.error("Failed to install hooks: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func removeHooks() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard var settings = (try? Data(contentsOf: url)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else {
            log.error("Failed to read settings.json for hook removal")
            return false
        }

        guard var hooks = settings["hooks"] as? [String: Any] else { return true }

        // Only remove NotchClaude entries, preserve all other hooks
        for key in ["PreToolUse", "PostToolUse"] {
            guard var entries = hooks[key] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    (h["command"] as? String)?.contains("notchclaude-hook") == true
                }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = entries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
            try data.write(to: url)
            log.info("NotchClaude hooks removed (other hooks preserved)")
            return true
        } catch {
            log.error("Failed to remove hooks: \(error.localizedDescription)")
            return false
        }
    }
}
