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

    // Display
    @AppStorage("showContextWindow") var showContextWindow: Bool = true
    @AppStorage("showContextWarning") var showContextWarning: Bool = false
    @AppStorage("contextWarningThreshold") var contextWarningThreshold: Double = 0.8
    @AppStorage("compactMode") var compactMode: Bool = false

    // Card sections
    @AppStorage("showSessionBadges") var showSessionBadges: Bool = true
    @AppStorage("showTimeline") var showTimeline: Bool = true
    @AppStorage("showReasoning") var showReasoning: Bool = true
    @AppStorage("showGitStatus") var showGitStatus: Bool = true
    @AppStorage("showDiffs") var showDiffs: Bool = true
    @AppStorage("showMessageInput") var showMessageInput: Bool = true

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
        case .read:    return autoApproveReads
        case .edit:    return autoApproveEdits
        case .command: return autoApproveBash
        case .agent:   return autoApproveAgents
        case .unknown: return false
        }
    }

    func shouldAutoApprove(toolName: String) -> Bool {
        shouldAutoApprove(category: .fromToolName(toolName))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedTab = 0

    private let tabs: [(String, String)] = [
        ("Approvals", "checkmark.shield"),
        ("Display", "rectangle.3.group"),
        ("Notifications", "bell"),
        ("General", "gear"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.0) { idx, tab in
                    Button { selectedTab = idx } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.1)
                                .font(.system(size: 12))
                            Text(tab.0)
                                .font(.system(size: 12, weight: selectedTab == idx ? .semibold : .regular))
                        }
                        .foregroundColor(selectedTab == idx ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == idx ? Color.accentColor.opacity(0.08) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.5)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch selectedTab {
                    case 0: approvalSettings
                    case 1: displaySettings
                    case 2: notificationSettings
                    case 3: generalSettings
                    default: approvalSettings
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 460, height: 500)
    }

    // MARK: - Approvals

    var approvalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Auto-Approve Tools") {
                VStack(spacing: 1) {
                    approvalRow(icon: "doc.text.magnifyingglass", title: "Read operations",
                                subtitle: "Read, Grep, Glob", binding: $settings.autoApproveReads)
                    approvalRow(icon: "pencil", title: "File edits",
                                subtitle: "Edit, Write", binding: $settings.autoApproveEdits)
                    approvalRow(icon: "terminal", title: "Bash commands",
                                subtitle: "Shell execution", binding: $settings.autoApproveBash,
                                warning: true)
                    approvalRow(icon: "person.2", title: "Subagents",
                                subtitle: "Agent tool", binding: $settings.autoApproveAgents, isLast: true)
                }
            }

            settingsSection("Timeout") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Auto-approve after:", selection: $settings.approvalTimeoutMinutes) {
                        Text("1 minute").tag(1)
                        Text("2 minutes").tag(2)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("Never").tag(0)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    captionText("Tools auto-approve after this timeout if you don't respond. \"Never\" requires manual action.")
                }
                .padding(12)
            }
        }
    }

    // MARK: - Display

    var displaySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Ring Indicator") {
                VStack(spacing: 1) {
                    settingsRow {
                        Toggle(isOn: $settings.showContextWindow) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Context window usage").font(.system(size: 13))
                                captionText("Show real token consumption. When off, shows activity state.")
                            }
                        }
                    }
                    settingsRow(isLast: true) {
                        Toggle(isOn: $settings.showContextWarning) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Context limit warning").font(.system(size: 13))
                                captionText("Banner when context exceeds threshold.")
                            }
                        }
                    }
                }
                if settings.showContextWarning {
                    HStack {
                        Text("Threshold:").font(.system(size: 12)).foregroundColor(.secondary)
                        Picker("", selection: $settings.contextWarningThreshold) {
                            Text("60%").tag(0.6); Text("70%").tag(0.7)
                            Text("80%").tag(0.8); Text("90%").tag(0.9)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            settingsSection("Layout") {
                settingsRow(isLast: true) {
                    Toggle(isOn: $settings.compactMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Compact mode").font(.system(size: 13))
                            captionText("Tighter spacing to fit more in the panel.")
                        }
                    }
                }
            }

            settingsSection("Card Sections") {
                VStack(spacing: 1) {
                    sectionToggle("Session badges", icon: "tag", binding: $settings.showSessionBadges)
                    sectionToggle("Task timeline", icon: "list.bullet", binding: $settings.showTimeline)
                    sectionToggle("Reasoning", icon: "brain", binding: $settings.showReasoning)
                    sectionToggle("Git status", icon: "arrow.triangle.branch", binding: $settings.showGitStatus)
                    sectionToggle("Inline diffs", icon: "doc.text.magnifyingglass", binding: $settings.showDiffs)
                    sectionToggle("Message input", icon: "keyboard", binding: $settings.showMessageInput, isLast: true)
                }
            }
        }
    }

    // MARK: - Notifications

    var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Sounds") {
                settingsRow(isLast: true) {
                    Toggle("Play sounds on events", isOn: $settings.playSounds)
                        .font(.system(size: 13))
                }
            }

            settingsSection("Desktop Notifications") {
                VStack(spacing: 1) {
                    settingsRow {
                        Toggle("Session complete", isOn: $settings.notifySessionComplete).font(.system(size: 13))
                    }
                    settingsRow {
                        Toggle("Waiting for input", isOn: $settings.notifyWaitingForInput).font(.system(size: 13))
                    }
                    settingsRow(isLast: true) {
                        Toggle("Approval needed", isOn: $settings.notifyApprovalNeeded).font(.system(size: 13))
                    }
                }
            }

            settingsSection("Cost Tracking") {
                VStack(spacing: 1) {
                    settingsRow(isLast: !settings.showCostTracking) {
                        Toggle(isOn: $settings.showCostTracking) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show cost estimates").font(.system(size: 13))
                                captionText("For API key users. Disable for Max/Pro plans.")
                            }
                        }
                    }
                    if settings.showCostTracking {
                        settingsRow(isLast: true) {
                            HStack {
                                Text("Alert threshold:").font(.system(size: 13))
                                Spacer()
                                TextField("", value: $settings.costAlertThreshold, format: .currency(code: "USD"))
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - General

    var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Startup") {
                settingsRow(isLast: true) {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .font(.system(size: 13))
                        .onChange(of: settings.launchAtLogin) { enabled in
                            if enabled { installLaunchAgent() } else { removeLaunchAgent() }
                        }
                }
            }

            settingsSection("Provider") {
                settingsRow(isLast: true) {
                    HStack {
                        Text("Default provider").font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $settings.defaultProviderRawValue) {
                            Text("Claude Code").tag(AgentProviderID.claude.rawValue)
                            Text("Codex").tag(AgentProviderID.codex.rawValue)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
            }

            settingsSection("Performance") {
                VStack(alignment: .leading, spacing: 8) {
                    settingsRow(isLast: true) {
                        HStack {
                            Text("Transcript poll interval").font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $settings.transcriptPollInterval) {
                                Text("1s").tag(1.0)
                                Text("2s").tag(2.0)
                                Text("5s").tag(5.0)
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }
                    captionText("How often NotchBar reads transcripts for token usage and reasoning updates.")
                        .padding(.horizontal, 12).padding(.bottom, 4)
                }
            }

            settingsSection("Integration") {
                VStack(spacing: 1) {
                    settingsRow {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hook script").font(.system(size: 13))
                                captionText("~/.notchbar/bin/notchbar-hook")
                            }
                            Spacer()
                            statusBadge(FileManager.default.fileExists(atPath:
                                FileManager.default.homeDirectoryForCurrentUser
                                    .appendingPathComponent(".notchbar/bin/notchbar-hook").path))
                        }
                    }
                    settingsRow(isLast: true) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Socket server").font(.system(size: 13))
                                captionText("~/.notchbar/notchbar.sock")
                            }
                            Spacer()
                            statusBadge(FileManager.default.fileExists(atPath:
                                FileManager.default.homeDirectoryForCurrentUser
                                    .appendingPathComponent(".notchbar/notchbar.sock").path))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reusable Components

    func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            content()
        }
    }

    func settingsRow<Content: View>(isLast: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                content()
                    .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if !isLast {
                Divider().padding(.leading, 12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    func approvalRow(icon: String, title: String, subtitle: String, binding: Binding<Bool>,
                     warning: Bool = false, isLast: Bool = false) -> some View {
        settingsRow(isLast: isLast) {
            Toggle(isOn: binding) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(title).font(.system(size: 13))
                            if warning {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            }
                        }
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    func sectionToggle(_ title: String, icon: String, binding: Binding<Bool>, isLast: Bool = false) -> some View {
        settingsRow(isLast: isLast) {
            Toggle(isOn: binding) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text(title).font(.system(size: 13))
                }
            }
        }
    }

    func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }

    func statusBadge(_ active: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(active ? "Active" : "Missing")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(active ? .green : .red)
        }
    }
}

// MARK: - Launch Agent

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
