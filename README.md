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
                    │  ● Claude  thinking...        62%    │
                    │    ┌ Deny ┐  ┌ Allow ┐               │
                    └───────────────────────────────────────┘
```

<p align="center">
  <strong>A plugin-based live dashboard for coding agents, crammed into your MacBook notch.</strong>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-000?logo=apple&logoColor=white"/>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white"/>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue"/>
</p>

---

## What is this

NotchBar turns the dead space around your MacBook notch into a live control surface for coding agents. See what your agent is doing, approve tool calls, and coordinate multiple agents — all without alt-tabbing back to a terminal like it's 2024.

## Plugins

| Plugin | Status | What it does |
|--------|--------|-------------|
| **Claude Code** | Stable | Live approvals, socket IPC, tool timeline, reasoning, session history |
| **Embedded Terminal** | Beta | Launch Claude Code sessions directly inside the notch panel with a full PTY terminal |
| **Conflict Detector** | Beta | Multi-agent file locking with MCP coordination server |
| **Codex** | Beta | Process discovery, transcript monitoring, managed profile (disabled by default) |

## Key Features

- **Embedded terminal** — launch Claude Code directly in the notch with a built-in PTY terminal
- **Approval doorbell** — full approval overlay with file preview, diffs, and clean Deny/Allow buttons (advanced options via disclosure chevron)
- **Conflict detection** — file locking across agents with an MCP server for proactive coordination
- **Multi-session cards** — run multiple agents side by side
- **Live tool timeline** — every tool invocation with status, elapsed time, and inline diffs (opt-in)
- **Token & cost tracking** — per-model cost estimation with context window usage ring (opt-in)
- **Git awareness** — branch name, changed file count per session
- **Hotkeys** — approve/reject from anywhere without switching windows
- **Warp, iTerm2, Terminal.app** — works with all major terminal emulators

## Install

### Download

Grab the `.dmg` from [Releases](https://github.com/lukataylo/NotchBar/releases).

### From Source

```bash
git clone https://github.com/lukataylo/NotchBar.git
cd NotchBar
./install.sh
```

Requires macOS 13+ and Xcode Command Line Tools.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd Shift C` | Toggle panel |
| `Cmd Shift Y` | Approve |
| `Cmd Shift N` | Reject |
| `Cmd Shift ]` | Next session |
| `Cmd Shift [` | Previous session |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       App Shell                              │
│  Infrastructure · Views · CardStack · ApprovalOverlay        │
├─────────────────────────────────────────────────────────────┤
│                     Plugin System                            │
│  ProviderCore · PluginRegistry · ProviderManager             │
├────────┬────────┬────────┬─────────────────────────────────┤
│Embedded│ Claude │ Codex  │ Conflict Detector               │
│Terminal│  Code  │        │                                 │
├────────┴────────┴────────┴─────────────────────────────────┤
│                    Shared Services                            │
│  Shell · SocketServer · CoordinationEngine · FileWatcher     │
│  GitIntegration · TranscriptReader · PTYSessionManager       │
└─────────────────────────────────────────────────────────────┘
```

One Swift file + one line of registration = new plugin. Run `/create-plugin` in Claude Code for the full guide.

## MCP Coordination Server

The Conflict Detector includes an MCP server that agents can connect to for proactive coordination:

| Tool | Description |
|------|-------------|
| `claim_file` | Claim a file before editing — blocked if another agent owns it |
| `release_file` | Release your lock so other agents can edit |
| `list_locks` | See all locked files and owners |
| `get_context` | Overview of active sessions, locks, and stats |

Install via Settings > Plugins > Conflict Detector > Configure > Set Up Server.

## FAQ

**Does it phone home?** No. Local-first. The only network call is checking GitHub for updates once a day, and even that's just a polite "hey, got anything new?"

**External monitors?** Yes. Creates a panel on every display. No-notch screens get a pill shape. Your notch jealousy ends here.

**What if NotchBar crashes?** Claude keeps working. The hook auto-approves when NotchBar is gone. Your agent has trust issues, not dependency issues.

**Do I need a MacBook with a notch?** Nope. Works on any Mac running macOS 13+. No notch = pill-shaped bar at the top of your screen. Honestly it looks better.

**All auto-approve settings are off by default?** Yes. Your agent earns trust, it doesn't start with it. Enable what you're comfortable with in Settings or during onboarding.

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
