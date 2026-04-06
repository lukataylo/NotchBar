# Create a NotchBar Plugin

You are helping the user create a new NotchBar plugin. NotchBar is a macOS app that monitors coding assistants and dev tools from the MacBook notch.

## Architecture

A plugin is a single Swift file that implements `AgentProviderController`. That's it. No build system, no manifest files, no IPC — just a class that creates `AgentSession` objects and updates them.

### The plugin contract

```swift
protocol AgentProviderController: AnyObject {
    var descriptor: ProviderDescriptor { get }
    func start()        // Called once when NotchBar launches (if plugin is enabled)
    func cleanup()      // Called on app quit

    // Optional — implement only what your plugin needs:
    func installIntegration() -> Bool
    func removeIntegration() -> Bool
    func approveAction(requestId: String, sessionId: UUID)
    func rejectAction(requestId: String, sessionId: UUID)
    func listPastSessions() -> [PastSession]
    func resumeSession(_ session: PastSession)
}
```

### The descriptor

Every plugin declares a `ProviderDescriptor` that tells NotchBar how to display it:

```swift
let descriptor = ProviderDescriptor(
    id: ProviderID("my-plugin"),       // Unique string ID
    displayName: "My Plugin",           // Shown in plugin store and cards
    shortName: "Mine",                  // Shown in collapsed notch
    executableName: "my-tool",          // Process name for pgrep (or "" if not applicable)
    settingsPath: nil,                  // Config file path (shown in plugin settings)
    instructionsFileName: "",           // e.g. "CLAUDE.md", ".cursorrules"
    integrationTitle: "",               // e.g. "Claude hooks"
    installActionTitle: "",             // e.g. "Install Hooks"
    removeActionTitle: "",              // e.g. "Remove Hooks"
    integrationSummary: "",             // Explains what install does
    accentColor: Color.blue,            // Plugin's brand color
    statusColor: brandSuccess,          // Usually brandSuccess (green)
    symbolName: "puzzlepiece",          // SF Symbol name for the icon
    capabilities: ProviderCapabilities(
        liveApprovals: false,           // Can intercept and approve/reject tool use?
        liveReasoning: false,           // Can extract reasoning from transcripts?
        sessionHistory: false,          // Can list and resume past sessions?
        integrationInstall: false       // Has installIntegration/removeIntegration?
    ),
    description: "One-line description shown in the plugin store.",
    stability: .beta,                   // .stable or .beta
    defaultEnabled: true                // false = user must manually enable
)
```

### Creating sessions

Plugins create `AgentSession` objects and add them to the shared `NotchState`:

```swift
let session = AgentSession(name: "project-name", projectPath: "/path/to/project", providerID: descriptor.id)
session.isActive = true
session.statusMessage = "Running"
session.pid = somePid  // optional, for lifecycle tracking
state.sessions.append(session)
```

### Updating sessions

Sessions are `ObservableObject` with `@Published` properties. Update them on the main thread:

```swift
session.statusMessage = "Building..."
session.appendTask(TaskItem(title: "cargo build", status: .running, toolName: "cargo"))
// Later:
session.tasks[idx].status = .completed
session.isCompleted = true
session.isActive = false
state.objectWillChange.send()  // Trigger UI refresh
```

### Key properties on AgentSession

- `isActive: Bool` — session is alive
- `isCompleted: Bool` — session finished
- `statusMessage: String` — shown in collapsed/expanded views
- `progress: Double` — 0.0 to 1.0, drives the progress ring
- `tasks: [TaskItem]` — timeline of tool invocations
- `lastReasoning: String?` — shown in reasoning section
- `inputTokens/outputTokens: Int` — token tracking
- `gitBranch/gitChangedFiles` — git status
- `pendingApproval: PendingApproval?` — for live approval plugins

### Registration

Add one line in `Infrastructure.swift` inside `applicationDidFinishLaunching`:

```swift
providerManager.register(MyPlugin(state: state))
```

### Available utilities

- `Shell.pgrep("process-name")` — returns `[Int32]` of matching PIDs
- `Shell.cwd(for: pid)` — returns the process's working directory
- `Shell.run("/path/to/exe", ["arg1", "arg2"])` — run a command, get stdout
- `Shell.readTail(path:from:)` — incremental file reading (for transcripts)
- `Shell.parseJSONLines(text:partialLine:)` — parse JSONL files
- `GitIntegration.fetchStatus(for: session)` — async git branch/status update

## Patterns

### Process monitor pattern (simplest)

Best for tools that run as visible processes. See `BuildMonitorProvider.swift` and `TestRunnerProvider.swift`.

1. Timer polls `Shell.pgrep()` every few seconds
2. New PIDs → create session, track in a `[Int32: TrackedInfo]` dict
3. Dead PIDs → mark session completed
4. Filter with `Shell.cwd()` to only track real project directories

### Transcript monitor pattern

Best for AI assistants that write log files. See `CodexProvider.swift`.

1. Discover process via pgrep
2. Find transcript file (e.g. `~/.codex/sessions/*.jsonl`)
3. Create a `LiveTranscriptReader` that tails the file
4. Parse entries into `TranscriptEntry` enum cases
5. Timer calls `reader.readNew()` and updates session properties

### Hook IPC pattern (most powerful)

Best for deep integration with tool approval flows. See `ClaudeCodeBridge.swift`.

1. Install a hook script in the tool's config
2. Hook script sends JSON events to NotchBar's Unix socket
3. Plugin handles events, creates approval UI, responds via socket
4. Requires `liveApprovals: true` in capabilities

## Instructions

When the user asks you to create a plugin:

1. Ask what tool/process they want to monitor
2. Determine the right pattern (process monitor for builds/commands, transcript for AI tools)
3. Create a single Swift file in `Sources/NotchBar/`
4. Pick an appropriate SF Symbol from https://developer.apple.com/sf-symbols/
5. Register it in `Infrastructure.swift`
6. Build with `swift build` and test

Keep plugins simple. A good plugin is 80-150 lines. Don't over-engineer.
