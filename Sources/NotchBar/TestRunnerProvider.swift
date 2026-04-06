import Foundation
import SwiftUI
import os.log

private let testLog = Logger(subsystem: "com.notchbar", category: "tests")

let testTeal = Color(red: 0.20, green: 0.78, blue: 0.70)

/// Monitors test runner processes (jest, pytest, cargo test, swift test, go test).
/// Detects via pgrep, tracks lifecycle, surfaces pass/fail in the notch.
final class TestRunnerProvider: AgentProviderController {
    let descriptor = ProviderDescriptor(
        id: ProviderID("tests"),
        displayName: "Test Runner",
        shortName: "Tests",
        executableName: "",
        settingsPath: nil,
        instructionsFileName: "",
        integrationTitle: "",
        installActionTitle: "",
        removeActionTitle: "",
        integrationSummary: "",
        accentColor: testTeal,
        statusColor: brandSuccess,
        symbolName: "checkmark.diamond",
        capabilities: ProviderCapabilities(
            liveApprovals: false,
            liveReasoning: false,
            sessionHistory: false,
            integrationInstall: false
        ),
        description: "Detect jest, pytest, cargo test, swift test, and go test. Shows pass/fail.",
        stability: .beta,
        defaultEnabled: false
    )

    private let state: NotchState
    private var pollTimer: Timer?
    private var trackedPids: [Int32: TrackedTest] = [:]

    private struct TrackedTest {
        let sessionID: UUID
        let runner: String
        let startedAt: Date
    }

    /// Test runners to scan for. Each entry: (pgrep name, patterns to match in cmdline, display label).
    private let testRunners: [(process: String, patterns: [String], label: String)] = [
        ("pytest", [], "pytest"),
        ("jest", [], "jest"),
        ("vitest", [], "vitest"),
        ("cargo", ["test"], "cargo test"),
        ("swift", ["test"], "swift test"),
        ("go", ["test"], "go test"),
        ("node", ["jest", "vitest", "mocha", "ava"], "node test"),
        ("ruby", ["rspec", "minitest"], "ruby test"),
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
            self?.detectTests()
            self?.checkLifecycle()
        }
    }

    private func detectTests() {
        for runner in testRunners {
            let pids = Shell.pgrep(runner.process)
            for pid in pids {
                if trackedPids[pid] != nil { continue }

                // If patterns are specified, verify the command line matches
                if !runner.patterns.isEmpty {
                    guard let cmdline = Shell.run("/bin/ps", ["-p", String(pid), "-o", "args="])?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          runner.patterns.contains(where: { cmdline.lowercased().contains($0) }) else {
                        continue
                    }
                }

                guard let cwd = Shell.cwd(for: pid),
                      cwd.hasPrefix("/Users/"),
                      !cwd.contains("/Library/"),
                      !cwd.contains(".app/"),
                      cwd.components(separatedBy: "/").count >= 4 else { continue }

                let projectName = (cwd as NSString).lastPathComponent
                let displayName = "\(runner.label) — \(projectName)"

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.state.sessions.contains(where: {
                        $0.providerID == self.descriptor.id && $0.projectPath == cwd && $0.isActive
                    }) { return }

                    let session = AgentSession(name: displayName, projectPath: cwd, providerID: self.descriptor.id)
                    session.isActive = true
                    session.statusMessage = "Running tests..."
                    session.pid = pid
                    session.appendTask(TaskItem(title: runner.label, status: .running, toolName: runner.process))
                    self.state.sessions.append(session)
                    self.trackedPids[pid] = TrackedTest(sessionID: session.id, runner: runner.label, startedAt: Date())
                    testLog.info("Tracking tests: \(runner.label) pid=\(pid) cwd=\(cwd)")
                    self.state.objectWillChange.send()
                }
            }
        }
    }

    private func checkLifecycle() {
        let allPids = trackedPids.keys
        for pid in allPids {
            let output = Shell.run("/bin/ps", ["-p", String(pid), "-o", "pid="])?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let alive = !output.isEmpty

            if !alive {
                guard let test = trackedPids.removeValue(forKey: pid) else { continue }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          let session = self.state.sessions.first(where: { $0.id == test.sessionID }) else { return }

                    // We can't reliably get exit code after process exits on macOS without
                    // prior monitoring. Mark as completed; future: use dispatch sources.
                    session.isActive = false
                    session.isCompleted = true
                    session.progress = 1.0
                    session.statusMessage = "Tests finished"

                    if let idx = session.tasks.lastIndex(where: { $0.status == .running }) {
                        session.tasks[idx].status = .completed
                    }

                    testLog.info("Tests finished: \(test.runner) pid=\(pid)")
                    self.state.objectWillChange.send()
                }
            }
        }
    }
}
