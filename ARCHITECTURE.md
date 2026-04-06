# NotchBar Architecture

## Design Philosophy

NotchBar is a lightweight macOS app that turns the MacBook notch into a live dashboard for coding agents. The architecture follows three principles:

1. **Plugins, not providers** — every coding assistant is a plugin. Adding support for a new tool is one Swift file + one line of registration.
2. **Capability-driven UI** — the UI never checks "is this Claude?" It asks "does this plugin support live approvals?" and degrades gracefully.
3. **Minimal dependencies** — pure Swift + Apple frameworks + SwiftTerm for embedded terminal. No node_modules, no build complexity.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│                       App Shell                              │
│  Infrastructure · Views · CardStack · Timeline               │
│  ApprovalOverlay · Settings · Components · Shapes            │
├─────────────────────────────────────────────────────────────┤
│                     Plugin System                            │
│  ProviderCore · PluginRegistry · ProviderManager             │
├────────┬────────┬────────┬────────┬────────┬────────┬───────┤
│Embedded│ Claude │ Codex  │ Cursor │ Build  │  Test  │Conflict│
│Terminal│  Code  │        │        │Monitor │ Runner │Detector│
├────────┴────────┴────────┴────────┴────────┴────────┴───────┤
│                    Shared Services                            │
│  Shell · HookManager · SocketServer · CoordinationEngine     │
│  GitIntegration · TranscriptReader · PTYSessionManager       │
│  TerminalHelper · FileWatcher · UpdateChecker                │
└─────────────────────────────────────────────────────────────┘
```

### App Shell

The UI layer. Knows nothing about specific plugins.

| File | Responsibility |
|------|---------------|
| `Infrastructure.swift` | Window panels, hotkeys, menu bar, app delegate, plugin registration |
| `Views.swift` | Collapsed bar, expanded view, notch shape, approval routing |
| `ApprovalOverlay.swift` | Doorbell overlay — file preview, edit diffs, 4-level approval buttons |
| `CardStack.swift` | Session cards (collapsed + expanded), card stack layout |
| `Timeline.swift` | Task timeline with status nodes and completion markers |
| `Components.swift` | Progress ring, diff views, dot progress, session state icons |
| `Shapes.swift` | Notch geometry, provider icons, NotchOwl branding |
| `Settings.swift` | Plugin store, display settings, general settings |
| `Onboarding.swift` | First-launch setup wizard |

### Plugin System

The bridge between plugins and the UI. Three files, no plugin-specific code.

| File | Responsibility |
|------|---------------|
| `ProviderCore.swift` | `ProviderID`, `ProviderDescriptor`, `ProviderCapabilities`, `AgentProviderController` protocol, `PluginRegistry` |
| `ProviderManager.swift` | Plugin lifecycle, action routing (approve/reject/allowAll/bypass) |
| `Models.swift` | `AgentSession`, `TaskItem`, `PendingApproval`, `NotchState` |

### Plugins

Each plugin is a single Swift file implementing `AgentProviderController`.

| Plugin | File | Pattern |
|--------|------|---------|
| Claude Code | `ClaudeCodeBridge.swift` | Hook IPC via Unix socket |
| Codex | `CodexProvider.swift` | Transcript monitoring |
| Cursor | `CursorProvider.swift` | Process + workspace discovery |
| Build Monitor | `BuildMonitorProvider.swift` | Process lifecycle |
| Test Runner | `TestRunnerProvider.swift` | Process lifecycle |

### Shared Utilities

| File | What it provides |
|------|-----------------|
| `Shell.swift` | `pgrep`, `cwd`, process runner, JSONL parsing, file tailing |
| `SocketServer.swift` | Unix domain socket server for hook IPC |
| `TranscriptReader.swift` | Claude transcript (.jsonl) parser |
| `CodexTranscriptReader.swift` | Codex transcript (.jsonl) parser |
| `GitIntegration.swift` | Branch, status, diff parsing |
| `TerminalHelper.swift` | Terminal.app / iTerm2 AppleScript bridge |
| `SessionHistory.swift` | Past session scanning and resume |
| `UpdateChecker.swift` | GitHub release polling |

## Plugin Contract

```swift
protocol AgentProviderController: AnyObject {
    var descriptor: ProviderDescriptor { get }  // Who am I, what can I do
    func start()                                 // Begin monitoring
    func cleanup()                               // Stop monitoring
    // Optional:
    func installIntegration() -> Bool
    func removeIntegration() -> Bool
    func approveAction(requestId:sessionId:)
    func rejectAction(requestId:sessionId:)
    func listPastSessions() -> [PastSession]
    func resumeSession(_:)
}
```

Registration is one line in `AppDelegate.applicationDidFinishLaunching`:

```swift
providerManager.register(MyPlugin(state: state))
```

## Capability Flags

| Flag | Meaning | Used by |
|------|---------|---------|
| `liveApprovals` | Can intercept tool use and show approve/reject UI | Claude Code |
| `liveReasoning` | Can extract reasoning from transcripts | Claude Code, Codex |
| `sessionHistory` | Can list and resume past sessions | Claude Code, Codex |
| `integrationInstall` | Has install/remove integration actions | Claude Code, Codex |

The UI checks these flags, not plugin IDs. A new plugin that sets `liveApprovals: true` automatically gets the full approval doorbell without any UI changes.

## Data Flow

### Hook IPC (Claude Code)

```
Claude Code hook → bash → nc -U notchbar.sock → SocketServer
  → ClaudeCodeBridge.handleSocketEvent (background thread)
  → auto-approve check → if manual: store response callback
  → dispatch to main → update AgentSession
  → SwiftUI observes @Published → re-render
  → user approves → response callback fires → hook script receives JSON
```

~9ms round-trip. Fail-open: if NotchBar isn't running, hook auto-approves.

### Process Monitor (Build/Test)

```
Timer (3s) → Shell.pgrep("cargo") → new PIDs found
  → Shell.cwd(for: pid) → create AgentSession
  → Timer (3s) → check if PID still alive
  → dead → mark session completed
```

### Transcript Monitor (Codex)

```
Timer (2s) → Shell.readTail(path, from: offset) → parse JSONL
  → TranscriptEntry cases → update AgentSession properties
  → SwiftUI re-renders
```

## Thread Safety

- `AgentSession` properties are `@Published` and must be updated on the main thread
- `ClaudeCodeBridge` uses `NSLock` + `withLock` helper for `sessionMap` and `runningTools`
- `SocketServer` uses `NSLock` for response coordination between callback and timeout
- Plugin timers run on main run loop; heavy work dispatches to `.utility` queues
