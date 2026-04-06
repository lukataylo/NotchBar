# Roadmap: Plugin Architecture

## Status: Core Implemented

The plugin system is live on the `plugin-architecture` branch. This document tracks what's built and what's next.

## What's Built

### Plugin System (Done)
- Open `ProviderID` (string-based, extensible without modifying core code)
- `PluginRegistry` with enable/disable per plugin, default-enabled control
- `ProviderDescriptor` with capabilities, stability labels, accent colors
- `AgentProviderController` protocol as the plugin interface
- Plugin store UI with per-plugin settings and configure panels
- `/create-plugin` Claude Code skill for guided plugin development

### Plugins (Done)
- **Claude Code** (stable) — hook IPC, live approvals, transcript parsing, session history
- **Codex** (beta) — process discovery, transcript monitoring, managed profile install
- **Cursor** (beta) — workspace detection, process monitoring
- **Build Monitor** (beta) — detects cargo, swift, npm, go, make builds
- **Test Runner** (beta) — detects jest, pytest, cargo test, swift test, go test

### Approval Doorbell (Done)
- Full-panel overlay with file preview, edit diffs, command preview
- Four approval levels: Deny, Allow Once, Allow All, Bypass
- Approval queue for multiple pending approvals
- Management tool category auto-approval

## What's Next

### Near-Term Plugin Ideas
| Plugin | Difficulty | Notes |
|--------|-----------|-------|
| Aider | Easy | Tail `.aider.chat.history.md`, process monitor pattern |
| Windsurf/Cascade | Easy | Electron app, similar to Cursor plugin |
| GitHub Copilot Chat | Medium | VS Code extension logs |
| CI Status | Medium | Poll `gh run list --json`, augment existing sessions |
| Deploy Tracker | Medium | Vercel/Railway/Fly API polling |
| Docker Monitor | Easy | `docker ps --format json` polling |

### External Plugin Support (Future)
The current plugin system requires plugins to be compiled into the app binary. A future extension would support external plugins via JSON-over-socket or stdin/stdout IPC:

- Plugin as any executable (Python, Node, Bash)
- Communication via stdin/stdout JSON-RPC
- NotchBar manages plugin lifecycle (launch, restart, stop)
- Plugin manifest in `~/.notchbar/plugins/<name>/plugin.json`
- Hot reload without restarting NotchBar

This is the next major architectural step, but the current compiled-in approach covers the most common tools well.

### UI Improvements
- Inline approval from collapsed bar (approve without expanding)
- Richer file preview in doorbell (syntax highlighting)
- Session grouping by project (multiple plugins monitoring the same repo)
- Keyboard navigation within the approval overlay
