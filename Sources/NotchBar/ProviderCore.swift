import Foundation
import SwiftUI

enum AgentProviderID: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }
}

struct ProviderCapabilities {
    let liveApprovals: Bool
    let liveReasoning: Bool
    let sessionHistory: Bool
    let integrationInstall: Bool
    let sendInput: Bool
    let resume: Bool
}

struct ProviderDescriptor {
    let id: AgentProviderID
    let displayName: String
    let shortName: String
    let executableName: String
    let settingsPath: String?
    let instructionsFileName: String
    let integrationTitle: String
    let installActionTitle: String
    let removeActionTitle: String
    let integrationSummary: String
    let accentColor: Color
    let statusColor: Color
    let symbolName: String
    let capabilities: ProviderCapabilities
}

enum ToolApprovalCategory {
    case read
    case edit
    case command
    case agent
    case unknown

    static func fromToolName(_ toolName: String) -> ToolApprovalCategory {
        switch toolName {
        case "Read", "Grep", "Glob":
            return .read
        case "Edit", "Write", "NotebookEdit":
            return .edit
        case "Bash":
            return .command
        case "Agent":
            return .agent
        default:
            return .unknown
        }
    }
}

protocol LiveTranscriptReader: AnyObject {
    func readNew() -> [TranscriptEntry]
}

protocol AgentProviderController: AnyObject {
    var descriptor: ProviderDescriptor { get }
    func start()
    func cleanup()
    func installIntegration() -> Bool
    func removeIntegration() -> Bool
    func sendInput(_ message: String, for session: AgentSession?)
    func sendQuickCommand(_ command: String, for session: AgentSession?)
    func approveAction(requestId: String, sessionId: UUID)
    func rejectAction(requestId: String, sessionId: UUID)
    func listPastSessions() -> [PastSession]
    func resumeSession(_ session: PastSession)
}

extension AgentProviderController {
    func installIntegration() -> Bool { false }
    func removeIntegration() -> Bool { false }
    func sendInput(_ message: String, for session: AgentSession?) {}
    func sendQuickCommand(_ command: String, for session: AgentSession?) { sendInput(command, for: session) }
    func approveAction(requestId: String, sessionId: UUID) {}
    func rejectAction(requestId: String, sessionId: UUID) {}
    func listPastSessions() -> [PastSession] { [] }
    func resumeSession(_ session: PastSession) {}
}

enum ProviderCatalog {
    static let claude = ProviderDescriptor(
        id: .claude,
        displayName: "Claude Code",
        shortName: "Claude",
        executableName: "claude",
        settingsPath: "~/.claude/settings.json",
        instructionsFileName: "CLAUDE.md",
        integrationTitle: "Claude hooks",
        installActionTitle: "Install Hooks",
        removeActionTitle: "Remove Hooks",
        integrationSummary: "Install NotchBar hook entries into Claude's settings so live tool events and approval requests appear in the notch.",
        accentColor: brandOrange,
        statusColor: brandSuccess,
        symbolName: "sparkles.rectangle.stack",
        capabilities: ProviderCapabilities(
            liveApprovals: true,
            liveReasoning: true,
            sessionHistory: true,
            integrationInstall: true,
            sendInput: true,
            resume: true
        )
    )

    static let codex = ProviderDescriptor(
        id: .codex,
        displayName: "Codex",
        shortName: "Codex",
        executableName: "codex",
        settingsPath: "~/.codex/config.toml",
        instructionsFileName: "AGENTS.md",
        integrationTitle: "Codex profile",
        installActionTitle: "Install Profile",
        removeActionTitle: "Remove Profile",
        integrationSummary: "Install a managed `notchbar` profile in Codex config. It preserves your defaults and adds a recommended workspace-write, on-request approval preset for monitored runs.",
        accentColor: codexBlue,
        statusColor: brandSuccess,
        symbolName: "terminal",
        capabilities: ProviderCapabilities(
            liveApprovals: false,
            liveReasoning: true,
            sessionHistory: true,
            integrationInstall: true,
            sendInput: true,
            resume: true
        )
    )

    static func descriptor(for id: AgentProviderID) -> ProviderDescriptor {
        switch id {
        case .claude:
            return claude
        case .codex:
            return codex
        }
    }
}
