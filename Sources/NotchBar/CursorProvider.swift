import Foundation
import SwiftUI
import os.log

private let cursorLog = Logger(subsystem: "com.notchbar", category: "cursor")

let cursorPurple = Color(red: 0.55, green: 0.36, blue: 0.96)

final class CursorProvider: AgentProviderController {
    let descriptor = ProviderDescriptor(
        id: .cursor,
        displayName: "Cursor",
        shortName: "Cursor",
        executableName: "Cursor",
        settingsPath: nil,
        instructionsFileName: ".cursorrules",
        integrationTitle: "Cursor monitoring",
        installActionTitle: "Enable",
        removeActionTitle: "Disable",
        integrationSummary: "Monitor Cursor agent and composer sessions by detecting running processes and reading workspace state.",
        accentColor: cursorPurple,
        statusColor: brandSuccess,
        symbolName: "cursorarrow.rays",
        capabilities: ProviderCapabilities(
            liveApprovals: false,
            liveReasoning: false,
            sessionHistory: false,
            integrationInstall: false
        ),
        description: "Process discovery and workspace monitoring for Cursor AI agent sessions.",
        stability: .beta
    )

    private let state: NotchState
    private var pollTimer: Timer?
    private var lifecycleTimer: Timer?
    private var knownPids: Set<Int32> = []

    init(state: NotchState) {
        self.state = state
    }

    func start() {
        detectRunningSessions()
        pollTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.transcriptPollInterval, repeats: true) { [weak self] _ in
            self?.detectRunningSessions()
            self?.pollSessions()
        }
        lifecycleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSessionLifecycle()
        }
    }

    func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
        lifecycleTimer?.invalidate()
        lifecycleTimer = nil
    }

    // MARK: - Session Detection

    /// Cursor runs as "Cursor" (Electron app). We look for the main process
    /// and derive the workspace from its command-line arguments or open windows.
    private func detectRunningSessions() {
        // Cursor's main process is "Cursor" on macOS
        let pids = Shell.pgrep("Cursor")
        guard !pids.isEmpty else { return }

        // Also try "cursor" (CLI) for completeness
        let cliPids = Shell.pgrep("cursor")
        let allPids = Set(pids + cliPids)

        // Find workspaces from Cursor helper processes or by checking open files
        let workspaces = detectCursorWorkspaces(pids: allPids)

        for workspace in workspaces {
            if existingSession(for: workspace.path) != nil { continue }

            let name = (workspace.path as NSString).lastPathComponent
            let session = AgentSession(name: name, projectPath: workspace.path, providerID: .cursor)
            session.isActive = true
            session.statusMessage = "Connected"
            session.pid = workspace.pid
            state.sessions.append(session)

            readInstructions(for: session)
            knownPids.insert(workspace.pid)
        }

        if state.activeSession == nil && !state.sessions.isEmpty {
            state.activeSessionIndex = 0
        }
    }

    private struct CursorWorkspace {
        let path: String
        let pid: Int32
    }

    private func detectCursorWorkspaces(pids: Set<Int32>) -> [CursorWorkspace] {
        var workspaces: [CursorWorkspace] = []
        var seenPaths: Set<String> = []

        for pid in pids {
            guard let cwd = Shell.cwd(for: pid),
                  cwd.hasPrefix("/Users/"),
                  !cwd.contains("/Library/"),
                  !cwd.contains("/Applications/"),
                  !cwd.contains(".app/"),
                  cwd.components(separatedBy: "/").count >= 4 else { continue }

            guard seenPaths.insert(cwd).inserted else { continue }
            workspaces.append(CursorWorkspace(path: cwd, pid: pid))
        }

        // Also check recently opened workspaces from Cursor's storage
        workspaces.append(contentsOf: detectFromCursorStorage(knownPaths: &seenPaths, pids: pids))

        return workspaces
    }

    /// Read Cursor's recently opened workspace storage to find active projects
    private func detectFromCursorStorage(knownPaths: inout Set<String>, pids: Set<Int32>) -> [CursorWorkspace] {
        let storagePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/storage.json")

        guard let data = try? Data(contentsOf: storagePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [CursorWorkspace] = []

        // Cursor stores recent folders in openedPathsList.workspaces3
        if let workspaces = json["openedPathsList"] as? [String: Any],
           let entries = workspaces["workspaces3"] as? [[String: Any]] {
            for entry in entries.prefix(5) {
                guard let folderUri = entry["folderUri"] as? String,
                      folderUri.hasPrefix("file://"),
                      let url = URL(string: folderUri) else { continue }

                let path = url.path
                guard knownPaths.insert(path).inserted,
                      FileManager.default.fileExists(atPath: path) else { continue }

                // Use any Cursor pid as the reference
                if let pid = pids.first {
                    results.append(CursorWorkspace(path: path, pid: pid))
                }
            }
        }

        return results
    }

    // MARK: - Polling

    private func pollSessions() {
        var changed = false

        for session in state.sessions where session.providerID == .cursor && session.isActive {
            // Check for .cursorrules changes
            if session.instructionsContent == nil {
                readInstructions(for: session)
            }

            // Update git status
            GitIntegration.fetchStatus(for: session)
            changed = true
        }

        if changed { state.objectWillChange.send() }
    }

    // MARK: - Lifecycle

    private func checkSessionLifecycle() {
        let activePids = Set(Shell.pgrep("Cursor") + Shell.pgrep("cursor"))

        for session in state.sessions where session.providerID == .cursor && session.isActive {
            if let pid = session.pid, !activePids.contains(pid) {
                session.isCompleted = true
                session.isActive = false
                session.statusMessage = "Completed"
                session.progress = 1.0
            }
        }
        state.objectWillChange.send()
    }

    // MARK: - Helpers

    private func existingSession(for projectPath: String) -> AgentSession? {
        state.sessions.first { $0.projectPath == projectPath && $0.providerID == .cursor }
    }

    private func readInstructions(for session: AgentSession) {
        Shell.readFirstExisting([
            session.projectPath + "/.cursorrules",
            session.projectPath + "/.cursor/rules",
        ]) { session.instructionsContent = $0 }
    }
}
