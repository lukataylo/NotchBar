import Foundation

class ProviderManager {
    static var shared: ProviderManager?

    let state: NotchState
    private var controllers: [ProviderID: any AgentProviderController] = [:]

    init(state: NotchState) {
        self.state = state
        Self.shared = self
    }

    // MARK: - Registration

    func register(_ controller: any AgentProviderController) {
        let id = controller.descriptor.id
        PluginRegistry.shared.register(controller.descriptor)
        controllers[id] = controller
    }

    // MARK: - Lifecycle

    func start() {
        for id in PluginRegistry.shared.enabledPluginIDs {
            controllers[id]?.start()
        }
    }

    func cleanup() {
        for (_, controller) in controllers {
            controller.cleanup()
        }
    }

    // MARK: - Accessors

    var providers: [any AgentProviderController] {
        PluginRegistry.shared.enabledPluginIDs.compactMap { controllers[$0] }
    }

    func controller(for id: ProviderID) -> (any AgentProviderController)? {
        guard PluginRegistry.shared.isEnabled(id) else { return nil }
        return controllers[id]
    }

    func controller(for session: AgentSession?) -> (any AgentProviderController)? {
        if let session { return controller(for: session.providerID) }
        return controller(for: AppSettings.shared.defaultProviderID)
    }

    // MARK: - Actions

    func installIntegration(for session: AgentSession? = nil) -> Bool {
        controller(for: session)?.installIntegration() ?? false
    }

    func removeIntegration(for session: AgentSession? = nil) -> Bool {
        controller(for: session)?.removeIntegration() ?? false
    }

    func approve(requestId: String, session: AgentSession) {
        controller(for: session)?.approveAction(requestId: requestId, sessionId: session.id)
    }

    func reject(requestId: String, session: AgentSession) {
        controller(for: session)?.rejectAction(requestId: requestId, sessionId: session.id)
    }

    /// Approve this request and auto-approve this tool category for the rest of the session
    func allowAll(requestId: String, toolName: String, session: AgentSession) {
        let category = ToolApprovalCategory.fromToolName(toolName)
        // Enable auto-approve for this category in global settings
        switch category {
        case .read:       AppSettings.shared.autoApproveReads = true
        case .edit:       AppSettings.shared.autoApproveEdits = true
        case .command:    AppSettings.shared.autoApproveBash = true
        case .agent:      AppSettings.shared.autoApproveAgents = true
        case .management: AppSettings.shared.autoApproveManagement = true
        case .unknown:    session.autoApproveAll = true
        }
        approve(requestId: requestId, session: session)
    }

    /// Approve this request and auto-approve everything for this session
    func bypass(requestId: String, session: AgentSession) {
        session.autoApproveAll = true
        approve(requestId: requestId, session: session)
    }

    func activeProviderDescriptor(for session: AgentSession? = nil) -> ProviderDescriptor? {
        if let session {
            return PluginRegistry.shared.descriptor(for: session.providerID)
        }
        return PluginRegistry.shared.descriptor(for: AppSettings.shared.defaultProviderID)
    }
}
