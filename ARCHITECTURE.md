# NotchBar Architecture

## Goal

Separate app UI from agent-specific runtime logic so NotchBar can support multiple local coding agents without turning every screen and model into a chain of `if provider == ...`.

## Layers

### 1. App shell

Files:

- `Infrastructure.swift`
- `Views.swift`
- `CardStack.swift`
- `Timeline.swift`
- `Settings.swift`

Responsibilities:

- windows, menu bar, hotkeys
- session rendering
- onboarding
- user preferences

### 2. Provider-neutral state

Files:

- `Models.swift`
- `ProviderCore.swift`
- `ProviderManager.swift`

Responsibilities:

- session state
- approval categories
- provider metadata
- action routing

### 3. Provider implementations

Files:

- `ClaudeCodeBridge.swift`
- `CodexProvider.swift`
- `TranscriptReader.swift`
- `CodexTranscriptReader.swift`

Responsibilities:

- session discovery
- transcript parsing
- approvals
- integration install/remove
- send input / resume

Current provider split:

- Claude: hook-driven live approvals and tool events through `~/.claude/settings.json`
- Codex: managed `notchbar` profile in `~/.codex/config.toml`, local session discovery, and transcript-derived task timelines

## Capability model

Not every provider should pretend to support every feature.

Current capability flags:

- `liveApprovals`
- `liveReasoning`
- `sessionHistory`
- `integrationInstall`
- `sendInput`
- `resume`

The UI should degrade based on capabilities instead of assuming Claude-style hooks everywhere.

## Current caveats

1. Codex approvals are still owned by Codex itself; NotchBar does not yet intercept and resolve them the way Claude hooks do.
2. Codex session association is currently keyed by project path, so multiple concurrent Codex runs in the same repo may collapse into one card.
3. Claude remains the richer approval path, but onboarding and integration management are now provider-specific instead of Claude-only.
