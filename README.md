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

NotchBar turns the dead space around your MacBook notch into a live control surface for coding agents. See what your agent is doing, approve tool calls, track costs, and coordinate multiple agents — without staring at terminal output.

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
│  Shell · HookManager · SocketServer · CoordinationEngine     │
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

Install via Settings > Plugins > Conflict Detector > Configure > Install MCP Server.

## FAQ

**Does it phone home?** No. Local-first. Only checks GitHub for updates once a day.

**External monitors?** Yes. Creates a panel on every display. No-notch screens get a pill shape.

**What if NotchBar crashes?** Claude keeps working. The hook auto-approves when NotchBar is gone.

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
