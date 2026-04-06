import Foundation
import SwiftUI
import os.log

private let buildLog = Logger(subsystem: "com.notchbar", category: "build")

let buildYellow = Color(red: 0.90, green: 0.75, blue: 0.20)

/// Monitors long-running build processes (cargo, swift, npm, go, make, gradle).
/// Detects builds via pgrep, tracks their cwd and lifecycle, surfaces
/// pass/fail in the notch so you don't have to watch the terminal.
final class BuildMonitorProvider: AgentProviderController {
    let descriptor = ProviderDescriptor(
        id: ProviderID("builds"),
        displayName: "Build Monitor",
        shortName: "Build",
        executableName: "",
        settingsPath: nil,
        instructionsFileName: "",
        integrationTitle: "",
        installActionTitle: "",
        removeActionTitle: "",
        integrationSummary: "",
        accentColor: buildYellow,
        statusColor: brandSuccess,
        symbolName: "hammer",
        capabilities: ProviderCapabilities(
            liveApprovals: false,
            liveReasoning: false,
            sessionHistory: false,
            integrationInstall: false
        ),
        description: "Detect cargo, swift, npm, go, and make builds. Shows pass/fail in the notch.",
        stability: .beta,
        defaultEnabled: false
    )

    private let state: NotchState
    private var pollTimer: Timer?
    private var trackedPids: [Int32: TrackedBuild] = [:]

    private struct TrackedBuild {
        let sessionID: UUID
        let command: String
        let startedAt: Date
    }

    /// Build tools to scan for. Each entry is (pgrep name, display label).
    private let buildTools: [(process: String, label: String)] = [
        ("cargo", "cargo"),
        ("swift-build", "swift build"),
        ("swiftc", "swiftc"),
        ("npm", "npm"),
        ("node", "node"),
        ("go", "go"),
        ("make", "make"),
        ("gradle", "gradle"),
        ("javac", "javac"),
        ("tsc", "tsc"),
    ]

    init(state: NotchState) {
        self.state = state
    }

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Polling

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.detectBuilds()
            self?.checkLifecycle()
        }
    }

    private func detectBuilds() {
        for tool in buildTools {
            let pids = Shell.pgrep(tool.process)
            for pid in pids {
                if trackedPids[pid] != nil { continue }

                guard let cwd = Shell.cwd(for: pid),
                      cwd.hasPrefix("/Users/"),
                      !cwd.contains("/Library/"),
                      !cwd.contains(".app/"),
                      cwd.components(separatedBy: "/").count >= 4 else { continue }

                // Filter out short-lived processes: check if still alive after a moment
                // (avoids flooding with every tiny compile step)
                guard isBuildProcess(pid: pid, tool: tool.process) else { continue }

                let projectName = (cwd as NSString).lastPathComponent
                let displayName = "\(tool.label) — \(projectName)"

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Don't duplicate if we already have a build for this cwd + tool
                    if self.state.sessions.contains(where: {
                        $0.providerID == self.descriptor.id && $0.projectPath == cwd && $0.isActive
                    }) { return }

                    let session = AgentSession(name: displayName, projectPath: cwd, providerID: self.descriptor.id)
                    session.isActive = true
                    session.statusMessage = "Building..."
                    session.pid = pid
                    session.appendTask(TaskItem(title: tool.label, status: .running, toolName: tool.process))
                    self.state.sessions.append(session)
                    self.trackedPids[pid] = TrackedBuild(sessionID: session.id, command: tool.label, startedAt: Date())
                    buildLog.info("Tracking build: \(tool.label) pid=\(pid) cwd=\(cwd)")
                    self.state.objectWillChange.send()
                }
            }
        }
    }

    /// Filter out non-build processes (e.g. "node" running a dev server isn't a build).
    private func isBuildProcess(pid: Int32, tool: String) -> Bool {
        // For node/npm, check if the command line contains "build" or "compile"
        if tool == "node" || tool == "npm" {
            guard let cmdline = Shell.run("/bin/ps", ["-p", String(pid), "-o", "args="])?
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            let lower = cmdline.lowercased()
            return lower.contains("build") || lower.contains("compile") || lower.contains("webpack")
                || lower.contains("esbuild") || lower.contains("rollup") || lower.contains("vite build")
        }
        return true
    }

    private func checkLifecycle() {
        let allPids = trackedPids.keys
        for pid in allPids {
            // Check if process is still running
            let alive = Shell.run("/bin/ps", ["-p", String(pid), "-o", "pid="]) != nil
                && !(Shell.run("/bin/ps", ["-p", String(pid), "-o", "pid="])?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            if !alive {
                guard let build = trackedPids.removeValue(forKey: pid) else { continue }

                // We cannot reliably recover exit status for unrelated processes after they exit.
                let exitCode = exitCodeForPid(pid)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          let session = self.state.sessions.first(where: { $0.id == build.sessionID }) else { return }

                    session.isActive = false
                    session.isCompleted = true
                    session.progress = 1.0
                    session.statusMessage = exitCode.map { $0 == 0 ? "Build succeeded" : "Build failed" } ?? "Build finished"

                    if let idx = session.tasks.lastIndex(where: { $0.status == .running }) {
                        if let exitCode {
                            session.tasks[idx].status = exitCode == 0 ? .completed : .rejected
                            session.tasks[idx].detail = "exit \(exitCode)"
                        } else {
                            session.tasks[idx].status = .completed
                            session.tasks[idx].detail = "exit status unavailable"
                        }
                    }

                    buildLog.info("Build finished: \(build.command) pid=\(pid) exit=\(exitCode.map(String.init) ?? "unknown")")
                    self.state.objectWillChange.send()
                }
            }
        }
    }

    private func exitCodeForPid(_ pid: Int32) -> Int? {
        // We are not the parent process, so the exit status is not available here.
        // Returning nil keeps the UI from incorrectly claiming success.
        return nil
    }
}
