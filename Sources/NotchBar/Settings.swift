import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Notifications
    @AppStorage("playSounds") var playSounds: Bool = true
    @AppStorage("notifySessionComplete") var notifySessionComplete: Bool = true
    @AppStorage("notifyWaitingForInput") var notifyWaitingForInput: Bool = true
    @AppStorage("notifyApprovalNeeded") var notifyApprovalNeeded: Bool = true
    @AppStorage("costAlertThreshold") var costAlertThreshold: Double = 5.0
    @AppStorage("showCostTracking") var showCostTracking: Bool = false  // Off by default (most users are on Max plan)

    // General
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("transcriptPollInterval") var transcriptPollInterval: Double = 2.0
    @AppStorage("defaultProvider") var defaultProviderRawValue: String = AgentProviderID.claude.rawValue

    // Approval settings
    @AppStorage("autoApproveReads") var autoApproveReads: Bool = true
    @AppStorage("autoApproveEdits") var autoApproveEdits: Bool = true
    @AppStorage("autoApproveBash") var autoApproveBash: Bool = true
    @AppStorage("autoApproveAgents") var autoApproveAgents: Bool = true
    @AppStorage("approvalTimeoutMinutes") var approvalTimeoutMinutes: Int = 5  // 0 = never

    func playSound(_ name: String) {
        guard playSounds else { return }
        NSSound(named: .init(name))?.play()
    }

    var defaultProviderID: AgentProviderID {
        get { AgentProviderID(rawValue: defaultProviderRawValue) ?? .claude }
        set { defaultProviderRawValue = newValue.rawValue }
    }

    /// Determines if a tool should be auto-approved based on settings
    func shouldAutoApprove(category: ToolApprovalCategory) -> Bool {
        switch category {
        case .read:
            return autoApproveReads
        case .edit:
            return autoApproveEdits
        case .command:
            return autoApproveBash
        case .agent:
            return autoApproveAgents
        case .unknown:
            return false
        }
    }

    func shouldAutoApprove(toolName: String) -> Bool {
        shouldAutoApprove(category: .fromToolName(toolName))
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TabView {
            approvalSettings
                .tabItem { Label("Approvals", systemImage: "checkmark.shield") }

            notificationSettings
                .tabItem { Label("Notifications", systemImage: "bell") }

            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
        }
        .padding(20)
        .frame(width: 460, height: 380)
    }

    var approvalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Approval Preferences")
                .font(.system(size: 15, weight: .bold))

            Text("Choose which tool types are auto-approved. Unchecked tools will show an approval card in the notch panel.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text("Claude uses these settings for live hook approvals. Codex still handles terminal approvals directly, but NotchBar keeps the same policy model for shared UI and future live integration.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            GroupBox("Auto-Approve") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.autoApproveReads) {
                        HStack {
                            Text("Read operations")
                            Text("(Read, Grep, Glob)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $settings.autoApproveEdits) {
                        HStack {
                            Text("File edits")
                            Text("(Edit, Write)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $settings.autoApproveBash) {
                        HStack {
                            Text("Bash commands")
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                        }
                    }

                    Toggle(isOn: $settings.autoApproveAgents) {
                        HStack {
                            Text("Subagents")
                            Text("(Agent tool)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("Timeout") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Auto-approve after:", selection: $settings.approvalTimeoutMinutes) {
                        Text("1 minute").tag(1)
                        Text("2 minutes").tag(2)
                        Text("5 minutes (default)").tag(5)
                        Text("10 minutes").tag(10)
                        Text("Never").tag(0)
                    }
                    .frame(width: 280)

                    Text("If you don't respond, the tool is auto-approved after this timeout. Set to 'Never' to always require manual approval.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(6)
            }

            Spacer()
        }
    }

    var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification Preferences")
                .font(.system(size: 15, weight: .bold))

            GroupBox("Sounds") {
                Toggle("Play sounds on events", isOn: $settings.playSounds)
                    .padding(6)
            }

            GroupBox("Desktop Notifications") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Session complete", isOn: $settings.notifySessionComplete)
                    Toggle("Waiting for input", isOn: $settings.notifyWaitingForInput)
                    Toggle("Approval needed", isOn: $settings.notifyApprovalNeeded)
                }
                .padding(6)
            }

            GroupBox("Cost Tracking (API key users)") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.showCostTracking) {
                        Text("Show cost estimates")
                    }
                    Text("Enable if using Claude Code with an API key. Disable for Max/Pro plan users.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if settings.showCostTracking {
                        HStack {
                            Text("Alert when session cost exceeds:")
                            TextField("", value: $settings.costAlertThreshold, format: .currency(code: "USD"))
                                .frame(width: 80)
                        }
                    }
                }
                .padding(6)
            }

            Spacer()
        }
    }

    var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.system(size: 15, weight: .bold))

            GroupBox("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { enabled in
                        if enabled { installLaunchAgent() } else { removeLaunchAgent() }
                    }
                    .padding(6)
            }

            GroupBox("Default Provider") {
                Picker("Provider:", selection: $settings.defaultProviderRawValue) {
                    Text("Claude Code").tag(AgentProviderID.claude.rawValue)
                    Text("Codex").tag(AgentProviderID.codex.rawValue)
                }
                .frame(width: 220)
                .padding(6)
            }

            GroupBox("Performance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transcript poll interval:")
                        Picker("", selection: $settings.transcriptPollInterval) {
                            Text("1s (fast)").tag(1.0)
                            Text("2s (default)").tag(2.0)
                            Text("5s (light)").tag(5.0)
                        }
                        .frame(width: 160)
                    }

                    Text("How often to read provider transcripts and token usage.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(6)
            }

            Spacer()
        }
    }
}

func installLaunchAgent() {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>com.notchbar.app</string>
        <key>ProgramArguments</key><array><string>\(execPath)</string></array>
        <key>RunAtLoad</key><true/>
    </dict>
    </plist>
    """
    try? plist.write(to: dir.appendingPathComponent("com.notchbar.app.plist"), atomically: true, encoding: .utf8)
}

func removeLaunchAgent() {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.notchbar.app.plist")
    try? FileManager.default.removeItem(at: path)
}
