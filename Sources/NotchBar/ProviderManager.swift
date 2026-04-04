import Foundation

class ProviderManager {
    static var shared: ProviderManager?

    let state: NotchState
    private let providerMap: [AgentProviderID: any AgentProviderController]

    init(state: NotchState) {
        self.state = state

        let claudeProvider = ClaudeCodeBridge(state: state)
        let codexProvider = CodexProvider(state: state)
        self.providerMap = [
            .claude: claudeProvider,
            .codex: codexProvider
        ]

        Self.shared = self
    }

    var providers: [any AgentProviderController] {
        AgentProviderID.allCases.compactMap { providerMap[$0] }
    }

    func start() {
        providers.forEach { $0.start() }
    }

    func cleanup() {
        providers.forEach { $0.cleanup() }
    }

    func controller(for id: AgentProviderID) -> (any AgentProviderController)? {
        providerMap[id]
    }

    func controller(for session: AgentSession?) -> (any AgentProviderController)? {
        if let session {
            return controller(for: session.providerID)
        }
        return controller(for: AppSettings.shared.defaultProviderID)
    }

    func installIntegration(for session: AgentSession? = nil) -> Bool {
        controller(for: session)?.installIntegration() ?? false
    }

    func removeIntegration(for session: AgentSession? = nil) -> Bool {
        controller(for: session)?.removeIntegration() ?? false
    }

    func sendInput(_ message: String, session: AgentSession?) {
        controller(for: session)?.sendInput(message, for: session)
    }

    func sendQuickCommand(_ command: String, session: AgentSession?) {
        controller(for: session)?.sendQuickCommand(command, for: session)
    }

    func approve(requestId: String, session: AgentSession) {
        controller(for: session)?.approveAction(requestId: requestId, sessionId: session.id)
    }

    func reject(requestId: String, session: AgentSession) {
        controller(for: session)?.rejectAction(requestId: requestId, sessionId: session.id)
    }

    func activeProviderDescriptor(for session: AgentSession? = nil) -> ProviderDescriptor {
        if let session {
            return session.provider
        }
        return ProviderCatalog.descriptor(for: AppSettings.shared.defaultProviderID)
    }
}
