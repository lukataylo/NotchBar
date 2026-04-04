# NotchBar

NotchBar turns the MacBook notch into a live control surface for local coding agents.

It gives Claude Code and Codex a compact, always-available status layer: what the agent is doing, what it changed, what it needs from you, and what the session is costing, without forcing you to live in the terminal.

**Tags**

`macOS` `SwiftUI` `Claude Code` `Codex` `developer-tools` `agent-ui` `menubar-app` `local-first`

## Why It Exists

Coding agents are powerful, but the default interaction model is still terminal-heavy and easy to lose track of.

NotchBar makes that workflow visible:

- See active sessions at a glance
- Track reasoning, tool activity, and progress in real time
- Surface approvals and interruptions without context switching
- Review diffs and file activity directly from the notch UI
- Keep Claude Code and Codex under one neutral app shell

The goal is not to replace the terminal. The goal is to make the terminal legible.

## What It Does

- Monitors local agent sessions and renders them in a compact notch panel
- Supports multiple providers through a provider-specific runtime layer
- Installs Claude hook integration for live tool and approval events
- Installs a managed Codex `notchbar` profile for a recommended monitored setup
- Parses transcript activity into timeline items, token usage, and cost estimates
- Lets you send input back to supported terminal sessions
- Keeps a session history so you can resume past work quickly

## Provider Support

### Claude Code

- Full live hook integration through `~/.claude/settings.json`
- Real-time tool lifecycle and approval cards
- Session history and resume support

### Codex

- Local session discovery from running `codex` processes
- Transcript-derived task and reasoning timeline from `~/.codex/sessions`
- Managed `profiles.notchbar` install/remove in `~/.codex/config.toml`
- Session history, monitored resume flow, and terminal input support

Codex still owns its own terminal approval UX today. NotchBar tracks the surrounding session state instead of pretending Claude-style hooks exist where they do not.

## Install

### Double-click installer

Use `Install.command`.

### Bash installer

```bash
cd ~/Documents/NotchBar
./install.sh
```

## Build

```bash
cd ~/Documents/NotchBar
swift build -c release
```

## Project Structure

```text
Sources/NotchBar/
├── ProviderCore.swift
├── ProviderManager.swift
├── ClaudeCodeBridge.swift
├── CodexProvider.swift
├── CodexTranscriptReader.swift
├── Models.swift
├── Onboarding.swift
├── Infrastructure.swift
├── Views.swift
├── Timeline.swift
└── Resources/
    └── NeutralAgentIcon.png
```

## Architecture

The app is split into three layers:

1. App shell
   Handles windows, menu bar UI, hotkeys, onboarding, and settings.
2. Provider-neutral state
   Defines shared session models, provider metadata, and routing.
3. Provider implementations
   Own provider-specific discovery, parsing, install/remove flows, resume behavior, and approvals.

This keeps the UI from collapsing into provider-specific conditionals everywhere and makes it practical to support both Claude and Codex in one app.

## Current Status

NotchBar is already usable, but the project is still evolving.

- Claude is currently the richer live-approval path
- Codex is fully supported for monitoring, history, input, and profile setup
- The app is designed to grow into a broader local-agent control surface, not stay tied to a single runtime

## License

See `LICENSE`.
