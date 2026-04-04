import SwiftUI

// MARK: - Timeline Spine

struct TimelineSpine: View {
    let tasks: [TaskItem]
    let pendingApproval: PendingApproval?
    let session: ClaudeSession

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.1.id) { idx, task in
                TimelineTaskNode(task: task, isLast: idx == tasks.count - 1 && pendingApproval == nil, session: session)
            }

            if let approval = pendingApproval {
                TimelineEventNode.approval(approval: approval, session: session)
            }

            if session.isCompleted {
                TimelineEventNode.completion(session: session)
            }
        }
    }
}

// MARK: - Timeline Task Node

struct TimelineTaskNode: View {
    let task: TaskItem
    let isLast: Bool
    let session: ClaudeSession

    @State private var expanded: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Spine column
            VStack(spacing: 0) {
                nodeCircle
                if !isLast {
                    Rectangle()
                        .fill(task.status == .running ? SessionState.running.stateColor.opacity(0.4) : Color.white.opacity(0.08))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if task.parentAgentId != nil {
                        Spacer().frame(width: 8)
                    }
                    if task.isAgentTask {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.purple.opacity(0.6))
                    }
                    Text(task.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    Text(task.elapsed)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    Text(task.status.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(task.status.color)
                    if task.diffFiles != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.2))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if task.diffFiles != nil {
                        withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                    }
                }

                if expanded, let diffs = task.diffFiles {
                    DiffContentView(files: diffs)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    var nodeCircle: some View {
        let nodeSize: CGFloat = task.status == .running || task.status == .pendingApproval ? 8 : 6
        let color = task.status.color

        if task.isAgentTask && task.status != .running {
            Circle()
                .stroke(Color.purple.opacity(0.6), lineWidth: 1)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
        } else {
            Circle()
                .fill(color)
                .frame(width: nodeSize, height: nodeSize)
                .padding(.top, task.status == .running ? 5 : 6)
                .modifier(PulseScale(active: task.status == .running))
        }
    }
}

private struct PulseScale: ViewModifier {
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulsing ? 1.3 : 1.0)
            .animation(active ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: pulsing)
            .onAppear { if active { pulsing = true } }
            .onChange(of: active) { newVal in pulsing = newVal }
    }
}

// MARK: - Timeline Event Node

struct TimelineEventNode: View {
    enum EventKind {
        case approvalRequired(PendingApproval, ClaudeSession)
        case sessionCompleted(ClaudeSession)
    }

    let kind: EventKind

    static func approval(approval: PendingApproval, session: ClaudeSession) -> TimelineEventNode {
        TimelineEventNode(kind: .approvalRequired(approval, session))
    }

    static func completion(session: ClaudeSession) -> TimelineEventNode {
        TimelineEventNode(kind: .sessionCompleted(session))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Spine interruption
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 2, height: 4)
                eventIcon
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 2, height: 4)
            }
            .frame(width: 24)

            // Event box
            eventContent
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    var eventIcon: some View {
        switch kind {
        case .approvalRequired(_, let session):
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 10))
                .foregroundColor(session.providerAccentColor)
                .frame(width: 16, height: 16)
        case .sessionCompleted:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(SessionState.completed.stateColor)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    var eventContent: some View {
        switch kind {
        case .approvalRequired(let approval, let session):
            approvalBox(approval: approval, session: session)
        case .sessionCompleted(let session):
            completionBox(session: session)
        }
    }

    func approvalBox(approval: PendingApproval, session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Approval Required")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(session.providerAccentColor)
                Spacer()
                Text(approval.toolName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
            }

            Text(approval.toolDescription)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            if let fp = approval.filePath {
                HStack(spacing: 4) {
                    Image(systemName: "doc").font(.system(size: 9))
                    Text(fp).font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.4))
            }

            if let cmd = approval.bashCommand {
                Text(cmd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
                    .lineLimit(5)
            }

            HStack(spacing: 12) {
                Button {
                    ProviderManager.shared?.approve(requestId: approval.requestId, session: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Approve")
                        Text("⌘Y").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    ProviderManager.shared?.reject(requestId: approval.requestId, session: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Reject")
                        Text("⌘N").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.red.opacity(0.6))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(12)
        .background(session.providerAccentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(session.providerAccentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    func completionBox(session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Session Complete")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SessionState.completed.stateColor)
                Spacer()
            }
            HStack(spacing: 12) {
                Text("\(session.tasks.count) tasks")
                if !session.costSummary.isEmpty { Text(session.costSummary).foregroundColor(session.providerAccentColor.opacity(0.6)) }
                Text(session.duration)
                if session.gitChangedFiles > 0 {
                    Text("\(session.gitChangedFiles) files changed").foregroundColor(.orange.opacity(0.6))
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.35))
        }
        .padding(10)
        .background(SessionState.completed.stateColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SessionState.completed.stateColor.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
