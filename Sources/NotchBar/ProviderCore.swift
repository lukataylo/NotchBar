import Foundation
import SwiftUI

// MARK: - Provider Identity

/// A lightweight, string-based provider identifier.
/// Replaces the old closed enum so new plugins can register without modifying core code.
struct ProviderID: Hashable, Codable, Identifiable, RawRepresentable {
    let rawValue: String
    var id: String { rawValue }

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    // Built-in IDs — convenience constants, not a closed set
    static let claude = ProviderID("claude")
    static let codex = ProviderID("codex")
    static let cursor = ProviderID("cursor")
    static let builds = ProviderID("builds")
    static let tests = ProviderID("tests")
}

// MARK: - Capabilities & Descriptor

struct ProviderCapabilities {
    let liveApprovals: Bool
    let liveReasoning: Bool
    let sessionHistory: Bool
    let integrationInstall: Bool
}

enum PluginStability {
    case stable, beta
}

struct ProviderDescriptor {
    let id: ProviderID
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
    let description: String
    let stability: PluginStability
    let defaultEnabled: Bool

    init(id: ProviderID, displayName: String, shortName: String, executableName: String,
         settingsPath: String?, instructionsFileName: String, integrationTitle: String,
         installActionTitle: String, removeActionTitle: String, integrationSummary: String,
         accentColor: Color, statusColor: Color, symbolName: String,
         capabilities: ProviderCapabilities, description: String,
         stability: PluginStability, defaultEnabled: Bool = true) {
        self.id = id; self.displayName = displayName; self.shortName = shortName
        self.executableName = executableName; self.settingsPath = settingsPath
        self.instructionsFileName = instructionsFileName; self.integrationTitle = integrationTitle
        self.installActionTitle = installActionTitle; self.removeActionTitle = removeActionTitle
        self.integrationSummary = integrationSummary; self.accentColor = accentColor
        self.statusColor = statusColor; self.symbolName = symbolName
        self.capabilities = capabilities; self.description = description
        self.stability = stability; self.defaultEnabled = defaultEnabled
    }
}

// MARK: - Tool Approval

enum ToolApprovalCategory {
    case read, edit, command, agent, management, unknown

    static func fromToolName(_ toolName: String) -> ToolApprovalCategory {
        switch toolName {
        case "Read", "Grep", "Glob": return .read
        case "Edit", "Write", "NotebookEdit": return .edit
        case "Bash": return .command
        case "Agent": return .agent
        case "TaskCreate", "TaskUpdate", "TaskGet", "TaskList",
             "TaskStop", "TaskOutput", "TodoWrite", "TodoRead",
             "Skill", "ToolSearch", "LSP",
             "WebSearch", "WebFetch": return .management
        default: return .unknown
        }
    }
}

// MARK: - Transcript Protocol

protocol LiveTranscriptReader: AnyObject {
    func readNew() -> [TranscriptEntry]
}

// MARK: - Provider Controller Protocol (the plugin interface)

protocol AgentProviderController: AnyObject {
    var descriptor: ProviderDescriptor { get }
    func start()
    func cleanup()
    func installIntegration() -> Bool
    func removeIntegration() -> Bool
    func approveAction(requestId: String, sessionId: UUID)
    func rejectAction(requestId: String, sessionId: UUID)
    func listPastSessions() -> [PastSession]
    func resumeSession(_ session: PastSession)
}

extension AgentProviderController {
    func installIntegration() -> Bool { false }
    func removeIntegration() -> Bool { false }
    func approveAction(requestId: String, sessionId: UUID) {}
    func rejectAction(requestId: String, sessionId: UUID) {}
    func listPastSessions() -> [PastSession] { [] }
    func resumeSession(_ session: PastSession) {}
}

// MARK: - Plugin Registry

/// Central registry for all providers (built-in and external).
/// Plugins register themselves here. The UI queries the registry to
/// know what's available, what's enabled, and how to display it.
class PluginRegistry: ObservableObject {
    static let shared = PluginRegistry()

    /// All registered descriptors, keyed by ID
    @Published private(set) var descriptors: [ProviderID: ProviderDescriptor] = [:]

    /// Ordered list of all known plugin IDs (registration order)
    @Published private(set) var allPluginIDs: [ProviderID] = []

    func register(_ descriptor: ProviderDescriptor) {
        let isNew = descriptors[descriptor.id] == nil
        descriptors[descriptor.id] = descriptor
        if !allPluginIDs.contains(descriptor.id) {
            allPluginIDs.append(descriptor.id)
        }
        // On first registration, apply the default enabled state
        if isNew && !descriptor.defaultEnabled {
            let key = "plugin.disabled.\(descriptor.id.rawValue)"
            if UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(true, forKey: key)
            }
        }
    }

    func descriptor(for id: ProviderID) -> ProviderDescriptor? {
        descriptors[id]
    }

    // MARK: - Enable/Disable

    func isEnabled(_ id: ProviderID) -> Bool {
        !UserDefaults.standard.bool(forKey: "plugin.disabled.\(id.rawValue)")
    }

    func setEnabled(_ id: ProviderID, enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: "plugin.disabled.\(id.rawValue)")
        objectWillChange.send()
    }

    var enabledPluginIDs: [ProviderID] {
        allPluginIDs.filter { isEnabled($0) }
    }
}

// Backward compatibility — existing code may still reference this name
typealias AgentProviderID = ProviderID
