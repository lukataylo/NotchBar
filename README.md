```
                    ┌──────────────────────────────────┐
                    │           ██  NotchBar  ██        │
                    │                                    │
                    │   your macbook notch was doing     │
                    │   nothing. now it runs your        │
                    │   coding agents.                   │
                    │                                    │
                    └────────────────┬───────────────────┘
                                     │
                    ┌────────────────┴───────────────────┐
                    │  ● Claude  thinking...     62%  $0.41 │
                    │  ○ Codex   Edit main.ts    38%  $0.12 │
                    └───────────────────────────────────────┘
```

<p align="center">
  <strong>A plugin-based live dashboard for local coding agents, crammed into your MacBook notch.</strong>
  <br/>
  <em>Because that little black rectangle should earn its keep.</em>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-000?logo=apple&logoColor=white"/>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white"/>
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=swift&logoColor=white"/>
  <img alt="Zero Dependencies" src="https://img.shields.io/badge/dependencies-0-brightgreen"/>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue"/>
</p>

---

## What is this

NotchBar turns the dead pixel real estate around your MacBook notch into a live control surface for coding agents and dev tools.

It shows you what your agent is doing, what it changed, what it needs from you, and what the session is costing — without forcing you to stare at terminal output.

> **Zero external dependencies.** Pure Swift + Apple frameworks. No node_modules were harmed.

## Plugins

NotchBar uses a plugin architecture. Each coding assistant or dev tool is a plugin that you can enable or disable independently. Disabled plugins use zero resources.

| Plugin | Status | What it does |
|--------|--------|-------------|
| **Claude Code** | Stable | Live approvals, socket IPC, tool timeline, reasoning, session history |
| **Codex** | Beta | Process discovery, transcript monitoring, managed profile install |
| **Cursor** | Beta | Workspace detection, process monitoring, git status |
| **Build Monitor** | Beta | Detects cargo, swift, npm, go, make builds. Shows pass/fail |
| **Test Runner** | Beta | Detects jest, pytest, cargo test, swift test. Shows results |

More plugins coming soon. See [Building Plugins](#building-plugins) to create your own.

## Key Features

- **Approval doorbell** — when a tool needs approval, the entire panel becomes a focused approval card with file preview, diff view, and 4-level actions (Deny, Allow Once, Allow All, Bypass)
- **Multi-session monitoring** — run Claude, Codex, and Cursor side by side in a card stack
- **Live tool timeline** — see every tool invocation with status, elapsed time, and inline diffs
- **Token & cost tracking** — optional per-model cost estimation for API key users
- **Git awareness** — branch, changed file count per session
- **Hotkey-driven** — approve/reject from anywhere without switching windows

## Install

### Recommended

Download the latest `.dmg` from [Releases](https://github.com/lukataylo/NotchBar/releases), open it, and drag `NotchBar.app` into Applications.

### From Source

```bash
git clone https://github.com/lukataylo/NotchBar.git
cd NotchBar
./install.sh
```

> **Requirements:** macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

### Build a DMG

```bash
./scripts/create_dmg.sh
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd Shift C` | Toggle the notch panel |
| `Cmd Shift Y` | Approve a pending tool use |
| `Cmd Shift N` | Reject a pending tool use |
| `Cmd Shift ]` | Next session |
| `Cmd Shift [` | Previous session |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    App Shell                         │
│  Infrastructure · Views · CardStack · Timeline       │
│  ApprovalOverlay · Settings · Components · Shapes    │
├─────────────────────────────────────────────────────┤
│              Plugin System                           │
│  ProviderCore · PluginRegistry · ProviderManager     │
├──────────┬──────────┬──────────┬──────────┬─────────┤
│  Claude  │  Codex   │  Cursor  │  Build   │  Test   │
│  Code    │          │          │  Monitor │  Runner  │
├──────────┴──────────┴──────────┴──────────┴─────────┤
│                  Shared Utilities                     │
│  Shell · GitIntegration · SocketServer               │
│  TranscriptReader · TerminalHelper                   │
└─────────────────────────────────────────────────────┘
```

**Plugin contract:** Implement `AgentProviderController`, return a `ProviderDescriptor`, register one line in `AppDelegate`. The UI picks up everything else automatically via capability flags.

### Hook IPC (Claude Code)

```
Claude Code → hook script (bash) → nc -U notchbar.sock → NotchBar
                                  ← JSON response ←
```

~9ms round-trip. If NotchBar isn't running, the hook auto-approves. Your agent is never stuck waiting.

## Building Plugins

Adding a plugin to NotchBar is one Swift file + one line of registration:

```bash
# In Claude Code, run:
/create-plugin
```

This loads the plugin development guide with the full protocol, patterns, and examples. Or read `.claude/commands/create-plugin.md` directly.

**Three patterns:**
1. **Process monitor** — detect via pgrep, track lifecycle (Build Monitor, Test Runner)
2. **Transcript monitor** — tail log files, parse entries (Codex, Cursor)
3. **Hook IPC** — install hooks, handle events via socket (Claude Code)

## Settings

NotchBar has three settings tabs:

- **Plugins** — enable/disable plugins, configure per-plugin settings (approval rules, integration install)
- **Display** — context window ring, compact mode, card section toggles
- **General** — launch at login, notifications, cost tracking, poll interval

## FAQ

**Does it phone home?**
No. NotchBar is local-first. The only network call is checking GitHub releases for updates once a day.

**Does it work on external monitors?**
Yes. NotchBar creates a panel on every connected display. Screens without a notch get a pill-shaped overlay.

**What happens if NotchBar crashes or quits?**
Claude Code keeps working. The hook script detects NotchBar is gone and auto-approves — your agent is never stuck waiting.

**Does it work with other terminals?**
Terminal.app and iTerm2 are supported for input injection. Session monitoring works regardless of terminal.

## Contributing

Issues and PRs welcome at [github.com/lukataylo/NotchBar](https://github.com/lukataylo/NotchBar).

## License

MIT — see [LICENSE](LICENSE).
