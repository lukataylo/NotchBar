import SwiftUI

// MARK: - Session Card Stack

struct SessionCardStack: View {
    @ObservedObject var state: NotchState
    let expandedIndex: Int

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(state.sessions.enumerated()), id: \.1.id) { idx, session in
                if idx == expandedIndex {
                    SessionCardExpanded(session: session, state: state, onCollapse: {
                        // Collapsing auto-selects next most urgent
                        state.expandedCardIndex = nil
                    })
                } else {
                    SessionCardCollapsed(session: session, onTap: {
                        state.selectCard(idx)
                    })
                }
            }
        }
    }
}

// MARK: - Collapsed Card

struct SessionCardCollapsed: View {
    @ObservedObject var session: ClaudeSession
    let onTap: () -> Void

    @State private var hovering = false

    private var compact: Bool { AppSettings.shared.compactMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Primary line
            HStack(spacing: 6) {
                SessionStateIcon(state: session.sessionState, size: compact ? 12 : 14)

                Text(session.name)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                if session.isStale {
                    Text("Idle \(session.staleDuration)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                } else if let model = session.modelName {
                    Text(shortModelName(model))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(3)
                }

                Spacer(minLength: 4)

                DotProgress(
                    completed: session.completedTaskCount,
                    running: session.runningTaskCount,
                    total: session.totalTaskCount
                )

                Group {
                    if AppSettings.shared.showContextWindow {
                        Text("\(Int(session.contextUsage * 100))%")
                            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ringColor(for: session))
                    } else {
                        Text(session.sessionState.label)
                            .font(.system(size: compact ? 8 : 9, weight: .semibold))
                            .foregroundColor(session.sessionState.stateColor)
                    }
                }

                if AppSettings.shared.showCostTracking && !session.costSummary.isEmpty {
                    Text(session.costSummary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(brandOrange.opacity(0.6))
                }

                Text(session.duration)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(hovering ? 0.4 : 0.2))
            }

            // Secondary line: last reasoning or status
            if !compact, let reasoning = session.lastReasoning ?? (session.isWaitingForUser ? session.lastResponse : nil) {
                Text(reasoning)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, compact ? 5 : 8)
        .background(Color.white.opacity(hovering ? 0.08 : 0.04))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
    }
}

// MARK: - Expanded Card

struct SessionCardExpanded: View {
    @ObservedObject var session: ClaudeSession
    @ObservedObject var state: NotchState
    var onCollapse: () -> Void

    @State private var messageText: String = ""
    @State private var showClaudeMd: Bool = false
    @State private var editingClaudeMd: Bool = false
    @State private var claudeMdDraft: String = ""
    @State private var nameHovering: Bool = false

    private var compact: Bool { AppSettings.shared.compactMode }

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Card Header
            cardHeader

            Divider().background(Color.white.opacity(0.06))

            // Badge bar
            if settings.showSessionBadges {
                badgeBar
            }

            // Git bar
            if settings.showGitStatus, session.gitBranch != nil {
                gitBar
            }

            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Timeline with tasks + events
                    if settings.showTimeline, !session.tasks.isEmpty || session.pendingApproval != nil {
                        TimelineSpine(
                            tasks: settings.showDiffs ? session.tasks : session.tasks.map { var t = $0; t.diffFiles = nil; return t },
                            pendingApproval: session.pendingApproval,
                            session: session
                        )
                        .padding(.horizontal, 8)
                    }

                    // Approval card always visible even if timeline is hidden
                    if !settings.showTimeline, let approval = session.pendingApproval {
                        TimelineEventNode.approval(approval: approval, session: session)
                            .padding(.horizontal, 8)
                    }

                    // Reasoning
                    if settings.showReasoning, let reasoning = session.lastReasoning {
                        reasoningSection(reasoning)
                    }

                    // Waiting indicator
                    if session.isWaitingForUser {
                        waitingIndicator
                    }

                    // Response
                    if let response = session.lastResponse, !response.isEmpty {
                        responseSection(response)
                    }

                    // CLAUDE.md viewer/editor
                    if showClaudeMd, let content = editingClaudeMd ? nil : session.claudeMdContent {
                        claudeMdViewer(content: content)
                    }
                    if showClaudeMd && editingClaudeMd {
                        claudeMdEditor()
                    }
                }
            }

            Divider().background(Color.white.opacity(0.06))

            // Stats bar
            statsBar

            // Approval hints or message input
            if session.pendingApproval != nil {
                approvalHints
            } else if settings.showMessageInput && session.isActive && !session.isCompleted && session.terminalAvailable {
                messageInput
            }
        }
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(session.sessionState.stateColor.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(10)
    }

    // MARK: - Card Header

    var cardHeader: some View {
        HStack(spacing: 8) {
            SessionStateIcon(state: session.sessionState, size: 16)

            HStack(spacing: 4) {
                Text(session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if nameHovering || session.isPinned {
                    Button { session.isPinned.toggle() } label: {
                        Image(systemName: session.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 9))
                            .foregroundColor(session.isPinned ? brandOrange : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .onHover { nameHovering = $0 }

            if session.isStale {
                Text("Idle \(session.staleDuration)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(3)
            }

            Spacer()

            ProgressRing(progress: ringProgress(for: session), size: 18, lineWidth: 2.5, color: ringColor(for: session))
                .overlay(
                    Group {
                        if AppSettings.shared.showContextWindow {
                            Text("\(Int(session.contextUsage * 100))")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                )

            if state.sessions.count > 1 {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, compact ? 5 : 8)
    }

    // MARK: - Badge Bar

    var badgeBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let mode = session.permissionMode {
                    Text(mode)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(permissionModeColor(mode))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(permissionModeColor(mode).opacity(0.15))
                        .cornerRadius(4)
                }

                if let model = session.modelName {
                    Text(shortModelName(model))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(4)
                }

                if session.isCompleted {
                    Text("COMPLETED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SessionState.completed.stateColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(SessionState.completed.stateColor.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                Button {
                    session.autoApproveAll.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: session.autoApproveAll ? "checkmark.shield.fill" : "checkmark.shield")
                        Text(session.autoApproveAll ? "Auto" : "Manual")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(session.autoApproveAll ? brandSuccess.opacity(0.8) : .white.opacity(0.3))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(session.autoApproveAll ? brandSuccess.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(session.autoApproveAll ? "All tools auto-approved for this session" : "Tools follow global approval settings")

                if session.claudeMdContent != nil {
                    Button {
                        showClaudeMd.toggle()
                        if showClaudeMd { editingClaudeMd = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                            Text("CLAUDE.md")
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(showClaudeMd ? brandOrange : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, compact ? 3 : 5)

            // Context warning banner
            if AppSettings.shared.showContextWarning && session.contextUsage >= AppSettings.shared.contextWarningThreshold {
                contextWarningBanner
            }
        }
    }

    var contextWarningBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange)
            Text("Context \(Int(session.contextUsage * 100))% — consider starting a new session")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Git Bar

    var gitBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundColor(.purple.opacity(0.6))
            Text(session.gitBranch ?? "")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            if session.gitChangedFiles > 0 {
                Text("\(session.gitChangedFiles) changed")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.purple.opacity(0.04))
    }

    // MARK: - Reasoning

    func reasoningSection(_ reasoning: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 9))
                .foregroundColor(brandOrange.opacity(0.6))
                .padding(.top, 2)
            Text(reasoning)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Waiting Indicator

    var waitingIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(SessionState.waitingForUser.stateColor).frame(width: 6, height: 6)
            Text("Claude is waiting for your input")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SessionState.waitingForUser.stateColor)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(SessionState.waitingForUser.stateColor.opacity(0.06))
    }

    // MARK: - Response

    func responseSection(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().background(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
                Text(response)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
        }
    }

    // MARK: - Stats Bar

    var statsBar: some View {
        Group {
            if !session.tokenSummary.isEmpty {
                HStack(spacing: 12) {
                    if AppSettings.shared.showContextWindow {
                        Label(session.contextSummary, systemImage: "brain")
                            .foregroundColor(contextColor(for: session.contextUsage).opacity(0.6))
                    } else {
                        Label(session.tokenSummary, systemImage: "number")
                    }
                    if AppSettings.shared.showCostTracking && !session.costSummary.isEmpty {
                        Label(session.costSummary, systemImage: "dollarsign.circle")
                            .foregroundColor(brandOrange.opacity(0.5))
                    }
                    Label(session.duration, systemImage: "clock")
                    Spacer()
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .padding(.horizontal, 12).padding(.vertical, compact ? 2 : 4)
            }
        }
    }

    // MARK: - CLAUDE.md Viewer

    func claudeMdViewer(content: String) -> some View {
        Group {
            Divider().background(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.instructionsFileName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Button("Edit") {
                        claudeMdDraft = content
                        editingClaudeMd = true
                    }
                    .font(.system(size: 10))
                    .foregroundColor(brandOrange)
                    .buttonStyle(.plain)
                }
                Text(content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
        }
    }

    // MARK: - CLAUDE.md Editor

    func claudeMdEditor() -> some View {
        Group {
            Divider().background(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Editing \(session.instructionsFileName)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(brandOrange)
                    Spacer()
                    Button("Cancel") { editingClaudeMd = false }
                        .font(.system(size: 10)).foregroundColor(.secondary).buttonStyle(.plain)
                    Button("Save") {
                        saveClaudeMd(content: claudeMdDraft, projectPath: session.projectPath)
                        session.claudeMdContent = claudeMdDraft
                        editingClaudeMd = false
                    }
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(brandOrange).buttonStyle(.plain)
                }
                TextEditor(text: $claudeMdDraft)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    func saveClaudeMd(content: String, projectPath: String) {
        let paths = [
            projectPath + "/\(session.instructionsFileName)",
            projectPath + "/.\(session.providerID.rawValue)/\(session.instructionsFileName)"
        ]
        let target = paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]
        try? content.write(toFile: target, atomically: true, encoding: .utf8)
    }

    // MARK: - Approval Hints

    var approvalHints: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("⌘⇧Y").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(brandSuccess)
                Text("Approve").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            }
            HStack(spacing: 4) {
                Text("⌘⇧N").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.red)
                Text("Reject").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Message Input

    var messageInput: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
            ZStack(alignment: .leading) {
                if messageText.isEmpty {
                    Text(session.isWaitingForUser ? "Reply to \(session.providerShortName)..." : "Message \(session.providerShortName)...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                TextField("", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .onSubmit { send() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(session.isWaitingForUser ? SessionState.waitingForUser.stateColor.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
    }

    func send() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messageText = ""
        DispatchQueue.global(qos: .userInitiated).async {
            TerminalHelper.sendInput(text, processName: "claude")
        }
    }

    // MARK: - Helpers

    func permissionModeColor(_ mode: String) -> Color {
        switch mode.lowercased() {
        case "plan": return .blue
        case "auto-accept", "autoaccept": return .green
        case "auto": return .purple
        default: return .white.opacity(0.5)
        }
    }
}

// MARK: - Empty State

struct EmptySessionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            NotchBarIcon()
                .opacity(0.3)
                .frame(width: 32, height: 32)
            Text("No active sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            Text("Start your agent in the terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
            Text("⌘⇧C to toggle")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.15))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared Helpers

func shortModelName(_ model: String) -> String {
    if model.contains("opus") { return "Opus" }
    if model.contains("sonnet") { return "Sonnet" }
    if model.contains("haiku") { return "Haiku" }
    return String(model.prefix(20))
}
