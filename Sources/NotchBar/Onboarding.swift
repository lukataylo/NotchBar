import SwiftUI
import os.log

private let log = Logger(subsystem: "com.notchbar", category: "onboarding")

struct OnboardingView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var currentStep = 0
    @State private var integrationInstalled = false
    @State private var integrationInstallFailed = false
    var onComplete: () -> Void

    var selectedProvider: ProviderDescriptor {
        PluginRegistry.shared.descriptor(for: settings.defaultProviderID)
            ?? PluginRegistry.shared.descriptors.values.first
            ?? ProviderDescriptor(
                id: .claude, displayName: "NotchBar", shortName: "NB",
                executableName: "", settingsPath: nil, instructionsFileName: "",
                integrationTitle: "", installActionTitle: "", removeActionTitle: "",
                integrationSummary: "", accentColor: brandOrange, statusColor: brandSuccess,
                symbolName: "puzzlepiece",
                capabilities: ProviderCapabilities(liveApprovals: false, liveReasoning: false, sessionHistory: false, integrationInstall: false),
                description: "",
                stability: .stable
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? selectedProvider.accentColor : Color.gray.opacity(0.3))
                        .frame(width: step == currentStep ? 24 : 8, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: hooksStep
                case 2: approvalsStep
                case 3: shortcutsStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer()
        }
        .frame(width: 440, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Step 1: Welcome

    var welcomeStep: some View {
        VStack(spacing: 20) {
            NotchBarIcon()
                .frame(width: 56, height: 56)

            Text("NotchBar")
                .font(.system(size: 28, weight: .bold))

            Text("Your notch now shows what your\ncoding agent is up to.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "eye", text: "See what your agent is doing in real time")
                featureRow(icon: "checkmark.shield", text: "Approve or deny tool calls without leaving your editor")
                featureRow(icon: "rectangle.stack", text: "Manage multiple sessions from one place")
                featureRow(icon: "display.2", text: "Works on every screen, with or without a notch")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer()

            Button(action: { withAnimation { currentStep = 1 } }) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedProvider.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: Install Integration

    var hooksStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(selectedProvider.accentColor)

            Text("Connect \(selectedProvider.displayName)")
                .font(.system(size: 22, weight: .bold))

            VStack(alignment: .leading, spacing: 12) {
                Text(selectedProvider.integrationSummary)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedProvider.integrationTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(selectedProvider.settingsPath ?? "No provider config path")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(4)
                }

                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text(providerSafetyText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            HStack(spacing: 12) {
                Button("Skip for now") {
                    withAnimation { currentStep = 2 }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: {
                    log.info("Onboarding: user chose to install integration")
                    let installOk = ProviderManager.shared?.installIntegration() ?? false

                    // Verify the hook script is executable (for providers that install hooks)
                    let hookOk: Bool = {
                        guard selectedProvider.capabilities.integrationInstall else { return true }
                        let hookPath = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent(".notchbar/bin/notchbar-hook").path
                        return FileManager.default.isExecutableFile(atPath: hookPath)
                    }()

                    if (installOk && hookOk) || !selectedProvider.capabilities.integrationInstall {
                        integrationInstalled = true
                        integrationInstallFailed = false
                        withAnimation { currentStep = 2 }
                    } else {
                        integrationInstallFailed = true
                        log.error("Onboarding: integration installation failed (install=\(installOk) hook=\(hookOk))")
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: integrationInstalled ? "checkmark" : "link")
                        Text(integrationInstalled ? "Connected!" : selectedProvider.installActionTitle)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(selectedProvider.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            if integrationInstallFailed {
                Text("Couldn't connect. Make sure \(selectedProvider.settingsPath ?? "the config file") is writable.")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 40)
            }

            Spacer().frame(height: 24)
        }
    }

    // MARK: - Step 3: Configure Approvals

    var approvalsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(selectedProvider.accentColor)

            Text("What needs your OK?")
                .font(.system(size: 22, weight: .bold))

            Text(approvalStepDescription)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.autoApproveReads) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Let it read files")
                                .font(.system(size: 13, weight: .medium))
                            Text("Read, Grep, Glob — just looking, no changes")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $settings.autoApproveEdits) {
                    HStack {
                        Image(systemName: "pencil")
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Let it edit files")
                                .font(.system(size: 13, weight: .medium))
                            Text("Edit, Write — changes your code")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $settings.autoApproveBash) {
                    HStack {
                        Image(systemName: "terminal")
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Let it run commands")
                                .font(.system(size: 13, weight: .medium))
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 9))
                                Text("Shell access — be careful with this one")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                Toggle(isOn: $settings.autoApproveAgents) {
                    HStack {
                        Image(systemName: "person.2")
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Let it launch subagents")
                                .font(.system(size: 13, weight: .medium))
                            Text("Spawns helpers that work on their own")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                if !selectedProvider.capabilities.liveApprovals {
                    Text("\(selectedProvider.displayName) handles approvals in its own terminal. These settings kick in for tools that support NotchBar approvals.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Approval timeout:")
                        .font(.system(size: 13))
                    Picker("", selection: $settings.approvalTimeoutMinutes) {
                        Text("1 min").tag(1)
                        Text("2 min").tag(2)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("Never").tag(0)
                    }
                    .frame(width: 100)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: { withAnimation { currentStep = 3 } }) {
                Text("Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedProvider.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 4: Shortcuts & Ready

    var shortcutsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundColor(selectedProvider.accentColor)

            Text("You're all set!")
                .font(.system(size: 22, weight: .bold))

            VStack(alignment: .leading, spacing: 14) {
                shortcutRow(keys: "Cmd Shift C", description: "Toggle the notch panel")
                shortcutRow(keys: "Cmd Shift Y", description: "Approve a change")
                shortcutRow(keys: "Cmd Shift N", description: "Reject a change")
                shortcutRow(keys: "Cmd ,", description: "Open Settings")
            }
            .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                Text("NotchBar lives in your menu bar.\nClick the icon anytime to access it.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            Spacer()

            Button(action: {
                log.info("Onboarding complete. Settings: reads=\(settings.autoApproveReads) edits=\(settings.autoApproveEdits) bash=\(settings.autoApproveBash) agents=\(settings.autoApproveAgents) timeout=\(settings.approvalTimeoutMinutes)min")
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                onComplete()
            }) {
                Text("Open NotchBar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedProvider.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedProvider.accentColor)
                    .frame(width: 24)
            Text(text)
                .font(.system(size: 13))
        }
    }

    var providerSafetyText: String {
        if selectedProvider.capabilities.liveApprovals {
            return "If NotchBar is closed, your agent keeps working — nothing gets stuck."
        }
        return "NotchBar watches \(selectedProvider.displayName) sessions without getting in the way."
    }

    var approvalStepDescription: String {
        if selectedProvider.capabilities.liveApprovals {
            return "Pick what your agent can do without asking.\nEverything else pauses for your OK."
        }
        return "Pick your default approval policy.\n\(selectedProvider.displayName) still asks in the terminal — NotchBar just shows you what's happening."
    }

    func shortcutRow(keys: String, description: String) -> some View {
        HStack(spacing: 16) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
                .frame(width: 160, alignment: .leading)
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}
