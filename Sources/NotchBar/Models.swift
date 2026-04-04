import AppKit
import SwiftUI
import Combine

// MARK: - Colors

let brandOrange = Color(red: 0.851, green: 0.467, blue: 0.341)
let brandSuccess = Color.green
let codexBlue = Color(red: 0.35, green: 0.62, blue: 0.96)
let claudeOrange = brandOrange
let claudeGreen = brandSuccess
let diffRedBg = Color(red: 0.35, green: 0.08, blue: 0.08)
let diffGreenBg = Color(red: 0.06, green: 0.25, blue: 0.06)
let diffRedText = Color(red: 1.0, green: 0.55, blue: 0.55)
let diffGreenText = Color(red: 0.55, green: 1.0, blue: 0.55)

// MARK: - NSScreen Extension

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var hasNotch: Bool {
        if #available(macOS 12.0, *) { return safeAreaInsets.top > 0 }
        return false
    }
}

// MARK: - Models

struct DiffFile: Identifiable {
    let id = UUID()
    var filename: String
    var lines: [DiffLine]
    var additions: Int { lines.filter { $0.kind == .addition }.count }
    var deletions: Int { lines.filter { $0.kind == .deletion }.count }
}

struct DiffLine: Identifiable {
    let id = UUID()

    enum Kind {
        case addition
        case deletion
        case context
        case hunkHeader
    }

    let kind: Kind
    let content: String
    let oldLineNum: Int?
    let newLineNum: Int?
}

struct TaskItem: Identifiable {
    let id = UUID()
    var title: String
    var status: TaskStatus
    var detail: String?
    var startedAt: Date = Date()
    var toolName: String?
    var filePath: String?
    var diffFiles: [DiffFile]?
    var isExpanded: Bool = false
    var parentAgentId: String?
    var requestId: String? = nil

    var elapsed: String {
        let seconds = Date().timeIntervalSince(startedAt)
        return seconds < 60 ? String(format: "%.1fs", seconds) : String(format: "%.0fm", seconds / 60)
    }

    var isAgentTask: Bool { toolName == "Agent" }

    enum TaskStatus {
        case running
        case completed
        case pendingApproval
        case rejected

        var label: String {
            switch self {
            case .running: return "Running"
            case .completed: return "Done"
            case .pendingApproval: return "Approve?"
            case .rejected: return "Rejected"
            }
        }

        var color: Color {
            switch self {
            case .running: return .orange
            case .completed: return brandSuccess
            case .pendingApproval: return brandOrange
            case .rejected: return .red
            }
        }

        var icon: String {
            switch self {
            case .running: return "circle.dotted"
            case .completed: return "checkmark.circle.fill"
            case .pendingApproval: return "exclamationmark.shield.fill"
            case .rejected: return "xmark.circle.fill"
            }
        }
    }
}

struct PendingApproval: Identifiable {
    let id = UUID()
    let requestId: String
    let toolName: String
    let toolDescription: String
    let filePath: String?
    let bashCommand: String?
    let isWriteOperation: Bool
    let timestamp: Date = Date()
    var diffFiles: [DiffFile]?
}

enum SessionState: Int, Comparable {
    case idle = 0
    case completed = 1
    case running = 2
    case waitingForUser = 3
    case needsApproval = 4

    static func < (lhs: SessionState, rhs: SessionState) -> Bool { lhs.rawValue < rhs.rawValue }

    var stateColor: Color {
        switch self {
        case .running:        return Color(red: 1.0, green: 0.65, blue: 0.0)
        case .waitingForUser: return Color(red: 1.0, green: 0.85, blue: 0.0)
        case .needsApproval:  return brandOrange
        case .completed:      return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .idle:           return Color(red: 0.4, green: 0.4, blue: 0.4)
        }
    }

    var icon: String {
        switch self {
        case .running:        return "circle.dotted"
        case .waitingForUser: return "questionmark.circle.fill"
        case .needsApproval:  return "exclamationmark.shield.fill"
        case .completed:      return "checkmark.circle.fill"
        case .idle:           return "circle"
        }
    }

    var label: String {
        switch self {
        case .running:        return "Running"
        case .waitingForUser: return "Waiting"
        case .needsApproval:  return "Approve?"
        case .completed:      return "Done"
        case .idle:           return "Idle"
        }
    }
}

// MARK: - Cost Estimation

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double

    static let claudePricing: [String: ModelPricing] = [
        "claude-opus-4-6":   ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0),
        "claude-sonnet-4-6": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0),
        "claude-haiku-4-5":  ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.0),
        "claude-sonnet-4-5": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0),
        "claude-opus-4-5":   ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0),
    ]

    static let openAIPricing: [String: ModelPricing] = [
        "gpt-5.4":       ModelPricing(inputPerMillion: 5.0, outputPerMillion: 15.0),
        "gpt-5.4-mini":  ModelPricing(inputPerMillion: 0.8, outputPerMillion: 2.4),
        "gpt-5.3-codex": ModelPricing(inputPerMillion: 1.5, outputPerMillion: 6.0),
        "gpt-5.2":       ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0),
    ]

    static func estimate(provider: AgentProviderID, model: String?, inputTokens: Int, outputTokens: Int) -> Double {
        let pricingTable: [String: ModelPricing]
        switch provider {
        case .claude:
            pricingTable = claudePricing
        case .codex:
            pricingTable = openAIPricing
        }

        let key = pricingTable.keys.first { model?.localizedCaseInsensitiveContains($0) == true }
        guard let selected = key.flatMap({ pricingTable[$0] }) else { return 0 }
        return (Double(inputTokens) / 1_000_000 * selected.inputPerMillion)
            + (Double(outputTokens) / 1_000_000 * selected.outputPerMillion)
    }
}

class AgentSession: Identifiable, ObservableObject {
    let id = UUID()
    let providerID: AgentProviderID

    @Published var name: String
    @Published var projectPath: String
    @Published var progress: Double = 0
    @Published var tasks: [TaskItem] = []
    @Published var statusMessage: String = "Idle"
    @Published var isActive: Bool = false
    @Published var isCompleted: Bool = false
    @Published var lastResponse: String? = nil
    @Published var lastReasoning: String? = nil
    @Published var inputTokens: Int = 0
    @Published var outputTokens: Int = 0
    @Published var isWaitingForUser: Bool = false
    @Published var transcriptPath: String? = nil
    @Published var permissionMode: String? = nil
    @Published var modelName: String? = nil
    @Published var instructionsContent: String? = nil
    @Published var estimatedCost: Double = 0
    @Published var gitBranch: String? = nil
    @Published var gitChangedFiles: Int = 0
    @Published var pendingApproval: PendingApproval? = nil
    @Published var terminalAvailable: Bool = false

    var transcriptReader: (any LiveTranscriptReader)? = nil
    var startedAt: Date = Date()
    var pid: Int32?

    init(name: String, projectPath: String, providerID: AgentProviderID) {
        self.name = name
        self.projectPath = projectPath
        self.providerID = providerID
    }

    var provider: ProviderDescriptor { ProviderCatalog.descriptor(for: providerID) }
    var providerDisplayName: String { provider.displayName }
    var providerShortName: String { provider.shortName }
    var providerAccentColor: Color { provider.accentColor }
    var instructionsFileName: String { provider.instructionsFileName }

    var claudeMdContent: String? {
        get { instructionsContent }
        set { instructionsContent = newValue }
    }

    var tokenSummary: String {
        guard inputTokens > 0 else { return "" }
        return "\(formatTokens(inputTokens))in / \(formatTokens(outputTokens))out"
    }

    var costSummary: String {
        guard estimatedCost > 0 else { return "" }
        if estimatedCost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", estimatedCost)
    }

    var duration: String {
        let seconds = Date().timeIntervalSince(startedAt)
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600)
    }

    func updateCost() {
        estimatedCost = ModelPricing.estimate(
            provider: providerID,
            model: modelName,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    var sessionState: SessionState {
        if pendingApproval != nil { return .needsApproval }
        if isWaitingForUser { return .waitingForUser }
        if isActive && !isCompleted { return .running }
        if isCompleted { return .completed }
        return .idle
    }

    var completedTaskCount: Int { tasks.filter { $0.status == .completed }.count }
    var runningTaskCount: Int { tasks.filter { $0.status == .running }.count }
    var totalTaskCount: Int { tasks.count }
}

typealias ClaudeSession = AgentSession

class NotchState: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var activeSessionIndex: Int = 0
    @Published var expandedScreenID: CGDirectDisplayID? = nil
    @Published var expandedCardIndex: Int? = nil
    @Published var lastManualSelectTime: Date? = nil

    var activeSession: AgentSession? {
        guard sessions.indices.contains(activeSessionIndex) else { return nil }
        return sessions[activeSessionIndex]
    }

    var hasActiveWork: Bool { sessions.contains { $0.isActive } }

    var resolvedExpandedIndex: Int {
        if let manual = expandedCardIndex, sessions.indices.contains(manual) {
            return manual
        }
        return autoExpandIndex
    }

    var autoExpandIndex: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.indices.max(by: { a, b in
            let sa = sessions[a].sessionState
            let sb = sessions[b].sessionState
            if sa != sb { return sa < sb }
            let ta = sessions[a].tasks.last?.startedAt ?? sessions[a].startedAt
            let tb = sessions[b].tasks.last?.startedAt ?? sessions[b].startedAt
            return ta < tb
        }) ?? 0
    }

    func selectCard(_ index: Int) {
        expandedCardIndex = index
        activeSessionIndex = index
        lastManualSelectTime = Date()
    }

    func reset() {
        sessions.removeAll()
        activeSessionIndex = 0
        expandedScreenID = nil
        expandedCardIndex = nil
    }
}
