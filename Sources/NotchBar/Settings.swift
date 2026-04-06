import Foundation
import SwiftUI
import os.log

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
    @AppStorage("showTimeline") var showTimeline: Bool = false
    @AppStorage("showReasoning") var showReasoning: Bool = false
    @AppStorage("showGitStatus") var showGitStatus: Bool = true
    @AppStorage("showDiffs") var showDiffs: Bool = true
    @AppStorage("showMessageInput") var showMessageInput: Bool = true

    // General
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("transcriptPollInterval") var transcriptPollInterval: Double = 2.0
    @AppStorage("defaultProvider") var defaultProviderRawValue: String = ProviderID.claude.rawValue

    // Conflict detector settings
    @AppStorage("conflictLockExpiryMinutes") var conflictLockExpiryMinutes: Int = 5
    @AppStorage("conflictAutoResolve") var conflictAutoResolve: Bool = false
    @AppStorage("conflictFileWatcher") var conflictFileWatcher: Bool = true

    // Approval settings
    @AppStorage("autoApproveReads") var autoApproveReads: Bool = true
    @AppStorage("autoApproveEdits") var autoApproveEdits: Bool = true
    @AppStorage("autoApproveBash") var autoApproveBash: Bool = true
    @AppStorage("autoApproveAgents") var autoApproveAgents: Bool = true
    @AppStorage("autoApproveManagement") var autoApproveManagement: Bool = true
    @AppStorage("approvalTimeoutMinutes") var approvalTimeoutMinutes: Int = 5  // 0 = never

    func playSound(_ name: String) {
        guard playSounds else { return }
        NSSound(named: .init(name))?.play()
    }

    var defaultProviderID: ProviderID {
        get {
            let id = ProviderID(rawValue: defaultProviderRawValue)
            if PluginRegistry.shared.isEnabled(id) { return id }
            // Fallback to first enabled plugin
            return PluginRegistry.shared.enabledPluginIDs.first ?? .claude
        }
        set { defaultProviderRawValue = newValue.rawValue }
    }

    /// Determines if a tool should be auto-approved based on settings
    func shouldAutoApprove(category: ToolApprovalCategory) -> Bool {
        switch category {
        case .read:       return autoApproveReads
        case .edit:       return autoApproveEdits
        case .command:    return autoApproveBash
        case .agent:      return autoApproveAgents
        case .management: return autoApproveManagement
        case .unknown:    return false
        }
    }

    func shouldAutoApprove(toolName: String) -> Bool {
        shouldAutoApprove(category: .fromToolName(toolName))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var registry = PluginRegistry.shared
    @State private var selectedTab = 0

    private let tabs: [(String, String)] = [
        ("Plugins", "puzzlepiece.extension"),
        ("Display", "rectangle.3.group"),
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
                    case 0: pluginLibrary
                    case 1: displaySettings
                    case 2: generalSettings
                    default: pluginLibrary
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 480, height: 540)
    }

    // MARK: - Plugin Store

    var pluginLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Enable the coding assistants you use. Disabled plugins use zero resources.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Plugin cards
            ForEach(registry.allPluginIDs) { pluginID in
                if let desc = registry.descriptor(for: pluginID) {
                    PluginCard(descriptor: desc, registry: registry)
                }
            }

            // More coming soon
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("More plugins coming soon — CI status, deploy tracking, and more.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.top, 4)
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

            settingsSection("Notifications") {
                VStack(spacing: 1) {
                    settingsRow {
                        Toggle("Play sounds", isOn: $settings.playSounds).font(.system(size: 13))
                    }
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
}

// MARK: - Plugin Card

struct PluginCard: View {
    let descriptor: ProviderDescriptor
    @ObservedObject var registry: PluginRegistry
    @ObservedObject var settings = AppSettings.shared
    @State private var hovering = false
    @State private var showSettings = false

    private var enabled: Bool { registry.isEnabled(descriptor.id) }
    private var hasSettings: Bool {
        descriptor.capabilities.liveApprovals || descriptor.capabilities.integrationInstall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    descriptor.accentColor.opacity(enabled ? 0.25 : 0.08),
                                    descriptor.accentColor.opacity(enabled ? 0.12 : 0.04),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: descriptor.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(enabled ? descriptor.accentColor : .gray.opacity(0.5))
                }

                // Name + description
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(descriptor.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(enabled ? .primary : .secondary)
                        Text(descriptor.stability == .stable ? "Stable" : "Beta")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(descriptor.stability == .stable ? .green : .orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background((descriptor.stability == .stable ? Color.green : Color.orange).opacity(0.12))
                            .cornerRadius(3)
                    }

                    Text(descriptor.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                // Enable toggle
                Toggle("", isOn: Binding(
                    get: { registry.isEnabled(descriptor.id) },
                    set: { registry.setEnabled(descriptor.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .padding(12)

            // Action bar: configure button + integration status
            if enabled {
                Divider().padding(.leading, 64)

                HStack(spacing: 10) {
                    // Integration status pill
                    if descriptor.capabilities.integrationInstall {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(integrationInstalled ? Color.green : Color.orange)
                                .frame(width: 5, height: 5)
                            Text(integrationInstalled ? "Installed" : "Not installed")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(integrationInstalled ? .green : .orange)
                        }

                        if !integrationInstalled {
                            Button("Install") {
                                _ = ProviderManager.shared?.controller(for: descriptor.id)?.installIntegration()
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(descriptor.accentColor)
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // Configure button
                    if hasSettings {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 10))
                                Text("Configure")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(showSettings ? descriptor.accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(showSettings ? descriptor.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }

            // Settings panel
            if enabled && showSettings {
                pluginSettingsPanel
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    hovering ? descriptor.accentColor.opacity(0.3) : Color.gray.opacity(0.15),
                    lineWidth: 0.5
                )
        )
        .onHover { hovering = $0 }
    }

    // MARK: - Settings Panel

    @ViewBuilder
    private var pluginSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top border with accent color
            Rectangle()
                .fill(descriptor.accentColor.opacity(0.3))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                if descriptor.capabilities.liveApprovals {
                    approvalSection
                }
                if descriptor.id == .conflicts {
                    conflictSettingsSection
                }
                if descriptor.capabilities.integrationInstall, let path = descriptor.settingsPath {
                    integrationSection(path: path)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }

    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Auto-Approve Rules", systemImage: "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))

            VStack(spacing: 6) {
                approvalRow("Read operations", detail: "Read, Grep, Glob", binding: $settings.autoApproveReads)
                approvalRow("File edits", detail: "Edit, Write", binding: $settings.autoApproveEdits)
                approvalRow("Shell commands", detail: "Bash execution", binding: $settings.autoApproveBash)
                approvalRow("Subagents", detail: "Agent tool", binding: $settings.autoApproveAgents)
                approvalRow("Management", detail: "Tasks, search, skills", binding: $settings.autoApproveManagement)
            }

            Divider()

            HStack {
                Text("Auto-approve timeout")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $settings.approvalTimeoutMinutes) {
                    Text("1 min").tag(1)
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("Never").tag(0)
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }
    }

    private func approvalRow(_ title: String, detail: String, binding: Binding<Bool>) -> some View {
        HStack {
            Toggle(isOn: binding) {
                Text(title)
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    private var conflictSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Coordination", systemImage: "arrow.triangle.merge")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))

            Toggle(isOn: $settings.conflictFileWatcher) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("File watcher").font(.system(size: 12))
                    Text("Detect when external editors modify locked files.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $settings.conflictAutoResolve) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-resolve conflicts").font(.system(size: 12))
                    Text("Automatically keep the lock owner after 12 seconds.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            HStack {
                Text("Lock expiry")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $settings.conflictLockExpiryMinutes) {
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("30 min").tag(30)
                }
                .labelsHidden()
                .frame(width: 90)
            }

            // Stats
            let stats = CoordinationEngine.shared.stats
            if stats.conflictsPrevented > 0 || stats.filesCoordinated > 0 {
                Divider()
                HStack(spacing: 16) {
                    Label("\(stats.conflictsPrevented) conflicts", systemImage: "shield.checkered")
                    Label("\(stats.filesCoordinated) files", systemImage: "doc.on.doc")
                    Label("\(stats.activeLocksCount) locks", systemImage: "lock")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
        }
    }

    private func integrationSection(path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Integration", systemImage: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))

            HStack(spacing: 8) {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(integrationInstalled ? "Reinstall" : "Install") {
                    _ = ProviderManager.shared?.controller(for: descriptor.id)?.installIntegration()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(descriptor.accentColor)
                .buttonStyle(.plain)
            }
        }
    }

    private var integrationInstalled: Bool {
        guard let path = descriptor.settingsPath else { return false }
        return FileManager.default.fileExists(atPath: NSString(string: path).expandingTildeInPath)
    }
}

// MARK: - Launch Agent

private let settingsLog = Logger(subsystem: "com.notchbar", category: "settings")

@discardableResult
func installLaunchAgent() -> Bool {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "NotchBar"
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
        try plist.write(to: dir.appendingPathComponent("com.notchbar.app.plist"), atomically: true, encoding: .utf8)
        return true
    } catch {
        settingsLog.error("Failed to install launch agent: \(error.localizedDescription)")
        return false
    }
}

@discardableResult
func removeLaunchAgent() -> Bool {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.notchbar.app.plist")
    do {
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        return true
    } catch {
        settingsLog.error("Failed to remove launch agent: \(error.localizedDescription)")
        return false
    }
}
