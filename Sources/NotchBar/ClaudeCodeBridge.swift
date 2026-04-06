import Foundation
import AppKit
import os.log
import UserNotifications
import ApplicationServices

private let log = Logger(subsystem: "com.notchbar", category: "bridge")

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

    let binDir: URL
    let state: NotchState

    var sessionMap: [String: UUID] = [:]
    var toolCounts: [String: Int] = [:]
    var runningTools: [String: (sessionUUID: UUID, taskTitle: String)] = [:]
    var transcriptTimer: Timer?
    var sessionLifecycleTimer: Timer?
    var gitTimer: Timer?
    var approvalTimers: [String: Timer] = [:]
    var socketServer: SocketServer?
    var pendingResponses: [String: (String) -> Void] = [:]

    init(state: NotchState) {
        self.state = state
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchbar")
        binDir = base.appendingPathComponent("bin")
        Self.shared = self
    }

    func start() {
        log.info("Bridge initializing")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        writeHookScript()
        requestNotificationPermission()

        // Socket server for IPC with hook scripts
        socketServer = SocketServer()
        socketServer?.onTimeout = { [weak self] event in
            let requestId = event.toolUseId ?? event.requestId ?? ""
            DispatchQueue.main.async {
                self?.pendingResponses.removeValue(forKey: requestId)
                self?.approvalTimers[requestId]?.invalidate()
                self?.approvalTimers.removeValue(forKey: requestId)
                if let session = self?.state.sessions.first(where: { $0.pendingApproval?.requestId == requestId }) {
                    session.pendingApproval = nil
                    session.statusMessage = "Timed out (auto-approved)"
                    self?.state.objectWillChange.send()
                }
            }
        }
        socketServer?.start { [weak self] event, hookType, respond in
            self?.handleSocketEvent(event, hookType: hookType, respond: respond)
        }

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
        let pids = Shell.pgrep("claude")
        guard !pids.isEmpty else { return }
        log.info("Found \(pids.count) claude process(es)")

        var sessions: [(name: String, path: String, pid: Int32)] = []
        for pid in pids {
            guard let cwd = Shell.cwd(for: pid),
                  cwd.hasPrefix("/Users/"),
                  !cwd.contains("/Library/"),
                  cwd.components(separatedBy: "/").count >= 4 else { continue }
            let name = (cwd as NSString).lastPathComponent
            guard !name.isEmpty else { continue }
            sessions.append((name: name, path: cwd, pid: pid))
        }
        // Deduplicate by path (multiple claude processes can share a project)
        var seen = Set<String>()
        sessions = sessions.filter { seen.insert($0.path).inserted }

        guard !sessions.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for s in sessions {
                if self.state.sessions.contains(where: { $0.projectPath == s.path && !$0.isCompleted }) { continue }
                let session = AgentSession(name: s.name, projectPath: s.path, providerID: .claude)
                session.isActive = true
                session.statusMessage = "Running"
                session.pid = s.pid
                session.terminalAvailable = Shell.isRunningInTerminal(pid: s.pid)
                self.state.sessions.append(session)
                self.readClaudeMd(for: session)
            }
            if !self.state.sessions.isEmpty { self.state.activeSessionIndex = 0 }
            self.state.objectWillChange.send()
        }
    }

    // MARK: - Session Lifecycle

    private func checkSessionLifecycle() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let activePids = Set(Shell.pgrep("claude"))

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
        Shell.readFirstExisting([
            session.projectPath + "/CLAUDE.md",
            session.projectPath + "/.claude/CLAUDE.md"
        ]) { session.instructionsContent = $0 }
    }

    // MARK: - Git Status Polling

    private func pollGitStatus() {
        for session in state.sessions where session.isActive && !session.isCompleted {
            GitIntegration.fetchStatus(for: session)
        }
    }

    // MARK: - Socket Event Handler (runs on background thread)

    private func handleSocketEvent(_ event: ClaudeCodeEvent, hookType: String, respond: @escaping (String) -> Void) {
        let toolName = event.toolName ?? "Tool"
        let toolUseId = event.toolUseId ?? event.requestId ?? UUID().uuidString

        if hookType == "pre-tool-use" || hookType == "pretooluse" {
            let shouldAuto = AppSettings.shared.shouldAutoApprove(toolName: toolName)
            // Check session-level auto-approve-all
            let sessionAutoApprove: Bool = {
                guard let sid = event.sessionId, let uuid = sessionMap[sid],
                      let session = state.sessions.first(where: { $0.id == uuid }) else { return false }
                return session.autoApproveAll
            }()

            if shouldAuto || sessionAutoApprove {
                respond("{\"decision\":\"approve\"}")
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.pendingResponses[toolUseId] = respond
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.handleEvent(event)
        }
    }

    // MARK: - Handle Event (must run on main thread)

    func handleEvent(_ event: ClaudeCodeEvent) {
        guard let sessionId = event.sessionId else {
            log.warning("Received event with no sessionId, ignoring")
            return
        }
        log.info("Event: \(event.hookType ?? event.hookEventName ?? "unknown") tool=\(event.toolName ?? "nil") session=\(String(sessionId.prefix(8)))")

        let cwd = event.cwd ?? ""
        let session: ClaudeSession
        if let uuid = sessionMap[sessionId], let existing = state.sessions.first(where: { $0.id == uuid }) {
            session = existing
        } else {
            // Only create sessions for real project directories
            guard cwd.hasPrefix("/Users/"), !cwd.contains("/Library/"),
                  cwd.components(separatedBy: "/").count >= 4,
                  FileManager.default.fileExists(atPath: cwd) else { return }
            let projectName = (cwd as NSString).lastPathComponent
            let s = AgentSession(name: projectName, projectPath: cwd, providerID: .claude)
            s.isActive = true; s.statusMessage = "Connected"
            // Try to find PID and detect terminal
            DispatchQueue.global(qos: .utility).async {
                for pid in Shell.pgrep("claude") {
                    if Shell.cwd(for: pid) == cwd {
                        DispatchQueue.main.async {
                            s.pid = pid
                            s.terminalAvailable = Shell.isRunningInTerminal(pid: pid)
                        }
                        break
                    }
                }
            }
            state.sessions.append(s)
            sessionMap[sessionId] = s.id
            toolCounts[sessionId] = 0
            session = s
            if state.sessions.count == 1 { state.activeSessionIndex = 0 }
            readClaudeMd(for: s)
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
            let needsApproval = !settings.shouldAutoApprove(toolName: toolName) && !session.autoApproveAll

            if needsApproval {
                log.info("Tool '\(toolName)' requires approval (request: \(toolUseId))")
                let approval = PendingApproval(
                    requestId: toolUseId,
                    toolName: toolName,
                    toolDescription: desc,
                    filePath: event.filePath,
                    bashCommand: event.bashCommand,
                    isWriteOperation: event.isWriteOperation
                )
                session.pendingApproval = approval
                session.appendTask(TaskItem(title: desc, status: .pendingApproval, toolName: toolName, filePath: event.filePath))
                session.statusMessage = "Awaiting approval: \(desc)"

                if state.expandedScreenID == nil {
                    let loc = NSEvent.mouseLocation
                    state.expandedScreenID = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.displayID
                }

                if settings.notifyApprovalNeeded {
                    sendNotification(title: "Approval Needed", body: desc)
                }
                settings.playSound("Submarine")

                let timeoutMinutes = settings.approvalTimeoutMinutes
                if timeoutMinutes > 0 {
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutMinutes * 60), repeats: false) { [weak self] _ in
                        self?.approveAction(requestId: toolUseId, sessionId: session.id)
                    }
                    approvalTimers[toolUseId] = timer
                }
            } else {
                session.appendTask(TaskItem(title: desc, status: .running, toolName: toolName, filePath: event.filePath))
                session.statusMessage = desc
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
                session.appendTask(TaskItem(title: desc, status: .completed, detail: detail, toolName: event.toolName, filePath: event.filePath))
            }
            session.lastToolActivityAt = Date()

            // Clear pending approval if this was it
            if session.pendingApproval?.requestId == toolUseId {
                session.pendingApproval = nil
            }

            // Fetch diff for write operations
            if event.isWriteOperation, let fp = event.filePath {
                fetchDiffForTask(filePath: fp, cwd: session.projectPath, session: session, toolUseId: toolUseId)
            }

            session.statusMessage = desc

        default: break
        }
        state.objectWillChange.send()
    }

    // MARK: - Approval Actions

    func approveAction(requestId: String, sessionId: UUID) {
        resolveApproval(requestId: requestId, sessionId: sessionId, decision: "approve", newStatus: .running)
    }

    func rejectAction(requestId: String, sessionId: UUID) {
        resolveApproval(requestId: requestId, sessionId: sessionId, decision: "deny", reason: "User rejected from NotchBar", newStatus: .rejected)
    }

    private func resolveApproval(requestId: String, sessionId: UUID, decision: String, reason: String? = nil, newStatus: TaskItem.TaskStatus) {
        log.info("\(decision.capitalized) request \(requestId)")

        // Respond via socket if the connection is waiting
        if let respond = pendingResponses.removeValue(forKey: requestId) {
            var json: [String: Any] = ["decision": decision]
            if let reason = reason { json["reason"] = reason }
            if let data = try? JSONSerialization.data(withJSONObject: json),
               let str = String(data: data, encoding: .utf8) {
                DispatchQueue.global(qos: .userInteractive).async { respond(str) }
            }
        }

        approvalTimers[requestId]?.invalidate()
        approvalTimers.removeValue(forKey: requestId)

        if let session = state.sessions.first(where: { $0.id == sessionId }) {
            if session.pendingApproval?.requestId == requestId {
                session.pendingApproval = nil
                if let idx = session.tasks.lastIndex(where: { $0.status == .pendingApproval }) {
                    session.tasks[idx].status = newStatus
                }
                session.statusMessage = decision == "approve" ? "Approved" : "Rejected"
            }
            state.objectWillChange.send()
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

                    if AppSettings.shared.showCostTracking {
                        let threshold = AppSettings.shared.costAlertThreshold
                        if session.estimatedCost >= threshold && (session.estimatedCost - ModelPricing.estimate(provider: session.providerID, model: session.modelName, inputTokens: input, outputTokens: 0)) < threshold {
                            sendNotification(title: "Cost Alert", body: "\(session.name) has exceeded \(String(format: "$%.2f", threshold))")
                        }
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

    // MARK: - Cleanup

    func cleanup() {
        log.info("Bridge cleaning up...")
        // Auto-approve any pending approvals so Claude Code isn't stuck
        for (_, timer) in approvalTimers { timer.invalidate() }
        approvalTimers.removeAll()
        for (_, respond) in pendingResponses {
            respond("{\"decision\":\"approve\"}")
        }
        pendingResponses.removeAll()
        socketServer?.stop()
        transcriptTimer?.invalidate()
        sessionLifecycleTimer?.invalidate()
        gitTimer?.invalidate()
        log.info("Bridge cleanup complete")
    }

    // MARK: - Hook Script

    @discardableResult
    func writeHookScript() -> Bool {
        let script = """
#!/bin/bash
# NotchBar hook — socket-based IPC for fast approvals
# Falls back to auto-approve if NotchBar is not running.
SOCK="$HOME/.notchbar/notchbar.sock"
HOOK_TYPE="${1:-notification}"
INPUT=$(cat -)

# Inject hook_type into the JSON
EVENT=$(echo "$INPUT" | awk -v ht="$HOOK_TYPE" '
  NR==1 { sub(/^[[:space:]]*\\{/, "{\\\"hook_type\\\":\\\"" ht "\\\",") }
  { print }
')

# Try socket connection to NotchBar
if [ -S "$SOCK" ]; then
    RESPONSE=$(echo "$EVENT" | nc -U "$SOCK" 2>/dev/null)
    if [ -n "$RESPONSE" ]; then
        echo "$RESPONSE"
        exit 0
    fi
fi

# Socket unavailable (NotchBar not running): auto-approve
[ "$HOOK_TYPE" = "pre-tool-use" ] && echo '{"decision":"approve"}'
"""
        let url = binDir.appendingPathComponent("notchbar-hook")
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
        let hookPath = binDir.appendingPathComponent("notchbar-hook").path
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var settings: [String: Any] = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        let notchEntry: (String) -> [String: Any] = { hookType in
            ["matcher": "", "hooks": [["type": "command", "command": "\(hookPath) \(hookType)"]]]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Merge: preserve existing hooks, remove old NotchBar/NotchClaude entries, add new ones
        for (key, hookType) in [("PreToolUse", "pre-tool-use"), ("PostToolUse", "post-tool-use")] {
            var entries = hooks[key] as? [[String: Any]] ?? []
            // Remove any existing notchbar or legacy notchclaude entries
            entries.removeAll { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    let cmd = h["command"] as? String ?? ""
                    return cmd.contains("notchbar-hook") || cmd.contains("notchclaude-hook")
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

        // Only remove NotchBar entries, preserve all other hooks
        for key in ["PreToolUse", "PostToolUse"] {
            guard var entries = hooks[key] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    (h["command"] as? String)?.contains("notchbar-hook") == true
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
            log.info("NotchBar hooks removed (other hooks preserved)")
            return true
        } catch {
            log.error("Failed to remove hooks: \(error.localizedDescription)")
            return false
        }
    }
}
