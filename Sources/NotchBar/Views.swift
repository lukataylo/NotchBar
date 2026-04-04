import SwiftUI

// MARK: - Collapsed View

struct CollapsedView: View {
    @ObservedObject var state: NotchState
    let hasNotch: Bool

    var body: some View {
        HStack(spacing: 0) {
            ActiveProviderIcon(session: state.activeSession)
                .frame(width: hasNotch ? 18 : 16, height: hasNotch ? 18 : 16)
                .fixedSize()
                .padding(.leading, hasNotch ? 20 : 14)

            Spacer(minLength: 8)

            if state.hasActiveWork, let session = state.activeSession {
                if session.pendingApproval != nil {
                    Text("Approve?")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(brandOrange)
                        .cornerRadius(4)
                } else if session.isWaitingForUser {
                    Text("Waiting for you")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(brandOrange).lineLimit(1)
                } else if session.isCompleted {
                    Text("Completed" + (AppSettings.shared.showCostTracking ? " \(session.costSummary)" : ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(brandSuccess).lineLimit(1)
                } else {
                    Text(session.statusMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.65)).lineLimit(1)
                }

                if state.sessions.count > 1 {
                    HStack(spacing: 3) {
                        ForEach(Array(state.sessions.enumerated()), id: \.1.id) { idx, s in
                            Circle().fill(idx == state.activeSessionIndex ? .white : progressColor(s).opacity(0.5))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }.padding(.leading, 4)
                }

                Spacer(minLength: 8)

                ProgressRing(progress: session.progress, size: hasNotch ? 16 : 14, lineWidth: 2, color: progressColor(session))
                    .fixedSize()
                    .padding(.trailing, hasNotch ? 26 : 14)
            } else {
                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Expanded View V2 (Card Stack + Color Rail)

struct ExpandedViewV2: View {
    @ObservedObject var state: NotchState
    let hasNotch: Bool
    var onCollapse: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider().background(Color.white.opacity(0.06))

            // Main content: Rail + Card Stack
            if state.sessions.isEmpty {
                EmptySessionView()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    SessionCardStack(
                        state: state,
                        expandedIndex: state.resolvedExpandedIndex
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Header

    var headerSection: some View {
        HStack(spacing: 8) {
            Button(action: onCollapse) {
                NotchBarIcon().frame(width: 20, height: 20)
            }.buttonStyle(.plain)

            Text(state.activeSession?.providerDisplayName ?? "NotchBar").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)

            Spacer()

            if state.sessions.count > 1 {
                Text("\(state.sessions.count) sessions")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }

            Button(action: onCollapse) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onCollapse() }
        .padding(.horizontal, 16).padding(.top, hasNotch ? 12 : 10).padding(.bottom, 6)
    }
}

// MARK: - Root Notch View

struct NotchView: View {
    @ObservedObject var state: NotchState
    let screenID: CGDirectDisplayID
    let hasNotch: Bool

    @State private var isHovering = false
    @State private var showExpanded = false

    var isExpanded: Bool { state.expandedScreenID == screenID }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showExpanded {
                    ExpandedViewV2(state: state, hasNotch: hasNotch, onCollapse: { collapse() })
                        .frame(width: 390)
                        .frame(maxHeight: 520)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    CollapsedView(state: state, hasNotch: hasNotch)
                        .frame(height: hasNotch ? 38 : 28)
                        .frame(width: hasNotch ? 300 : (state.hasActiveWork ? 220 : 130))
                        .contentShape(Rectangle())
                        .onTapGesture { expand() }
                }
            }
            .clipShape(notchShape)
            .background(notchShape.fill(Color.black))
            .overlay(borderOverlay)
            .shadow(color: (hasNotch && !showExpanded) ? .clear : .black.opacity(0.3), radius: 5, y: 2)
            .animation(.easeInOut(duration: 0.25), value: showExpanded)
            .animation(.easeInOut(duration: 0.15), value: state.hasActiveWork)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { isHovering = $0 }
        .onChange(of: isExpanded) { expanded in
            withAnimation(.easeInOut(duration: expanded ? 0.25 : 0.2)) { showExpanded = expanded }
        }
    }

    var notchShape: NotchCollapsedShape {
        NotchCollapsedShape(bottomRadius: showExpanded ? 18 : (hasNotch ? 18 : 12))
    }

    @ViewBuilder var borderOverlay: some View {
        if hasNotch && !showExpanded { Color.clear }
        else { notchShape.stroke(isHovering ? brandOrange.opacity(0.2) : Color.white.opacity(0.04), lineWidth: 0.5) }
    }

    func expand() { state.expandedScreenID = screenID }
    func collapse() { state.expandedScreenID = nil }
}
