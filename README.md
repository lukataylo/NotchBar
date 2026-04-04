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
  <strong>A live dashboard for local coding agents, crammed into your MacBook notch.</strong>
  <br/>
  <em>Because that little black rectangle should earn its keep.</em>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-000?logo=apple&logoColor=white"/>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white"/>
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=swift&logoColor=white"/>
  <img alt="Zero Dependencies" src="https://img.shields.io/badge/dependencies-0-brightgreen"/>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue"/>
  <img alt="Lines of Code" src="https://img.shields.io/badge/lines-~4.8k-yellow"/>
</p>

---

## What is this

NotchBar turns the dead pixel real estate around your MacBook notch into a live control surface for **Claude Code** and **Codex**.

It shows you what your agent is doing, what it changed, what it needs from you, and what the session is costing — without forcing you to stare at terminal output like it's 1987.

> **Zero external dependencies.** Pure Swift + Apple frameworks. No node_modules were harmed.

## Why

Coding agents are powerful. The default interaction model is still "hope you noticed that one line scroll by in the terminal."

NotchBar fixes that:

- **See sessions at a glance** — status, progress, cost, model, all in the notch
- **Handle approvals without context switching** — approve or reject tool use from the notch panel or via hotkeys
- **Track everything** — reasoning, tool activity, diffs, token usage, git changes
- **Multi-agent** — run Claude and Codex side by side, each in their own card
- **Resume past work** — session history lets you pick up where you left off

The goal isn't to replace the terminal. It's to make the terminal *legible*.

## Install

### Recommended

Download the packaged [`NotchBar-0.1.0.dmg`](https://github.com/lukataylo/NotchBar/releases/download/v0.1.0/NotchBar-0.1.0.dmg), open it, and drag `NotchBar.app` into `Applications`.

Because current builds are unsigned, macOS may warn on first launch. If it does, right-click the app and choose `Open`, or use `System Settings → Privacy & Security → Open Anyway`.

### Option A: Double-click

```
Open Install.command
```
That's it. It builds, bundles, copies to `/Applications`, and launches.

### Option B: Terminal

```bash
git clone https://github.com/lukataylo/NotchBar.git
cd NotchBar
./install.sh
```

If a prebuilt app exists in `dist/`, the installer uses it first. Otherwise it builds the app locally with Swift.

> **Requirements:** macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).
> First launch may trigger Gatekeeper — open System Settings → Privacy & Security → Open Anyway.

### Build a DMG

```bash
cd ~/Documents/NotchBar
./scripts/create_dmg.sh
```

This produces:

```text
dist/NotchBar.app
dist/NotchBar-0.1.0.dmg
```

### Detailed install notes

See [INSTALL.md](INSTALL.md).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd Shift C` | Toggle the notch panel |
| `Cmd Shift Y` | Approve a pending tool use |
| `Cmd Shift N` | Reject a pending tool use |
| `Cmd ,` | Open Settings |

## Provider Support

### Claude Code — full live integration

- Hook-driven real-time tool events and approval cards via `~/.claude/settings.json`
- Approve/reject directly from the notch (no terminal context switch)
- Session history and resume from `~/.claude/projects/`
- Reasoning summaries, token tracking, cost estimation

### Codex — monitored sessions

- Auto-discovers running `codex` processes
- Parses transcript activity from `~/.codex/sessions/*.jsonl`
- Managed `notchbar` profile install/remove in `~/.codex/config.toml`
- Session history, resume flow, terminal input injection
- Task timeline with command tracking and status

> Codex still owns its own terminal approval UX. NotchBar tracks the session around it rather than pretending Claude-style hooks exist where they don't.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    App Shell                         │
│  Infrastructure · Views · CardStack · Timeline       │
│  Settings · Onboarding · Components · Shapes         │
├─────────────────────────────────────────────────────┤
│               Provider-Neutral State                 │
│  Models · ProviderCore · ProviderManager             │
├──────────────────────┬──────────────────────────────┤
│   Claude Provider    │      Codex Provider           │
│  ClaudeCodeBridge    │  CodexProvider                │
│  TranscriptReader    │  CodexTranscriptReader        │
│  SessionHistory      │                               │
├──────────────────────┴──────────────────────────────┤
│                  Shared Utilities                     │
│  Shell · TerminalHelper · GitIntegration             │
│  UpdateChecker                                       │
└─────────────────────────────────────────────────────┘
```

Three layers, zero provider-specific conditionals in the UI:

1. **App shell** — windows, panels, menu bar, hotkeys, SwiftUI views
2. **Provider-neutral state** — shared session models, capability flags, action routing
3. **Provider implementations** — discovery, transcript parsing, approvals, integration install

Each provider declares capabilities (`liveApprovals`, `liveReasoning`, `sessionHistory`, `sendInput`, `resume`, `integrationInstall`) and the UI degrades gracefully based on what's available.

## Project Structure

```
Sources/NotchBar/
├── main.swift                  # entry point
├── Infrastructure.swift        # panels, hotkeys, menu bar, app delegate
├── Views.swift                 # collapsed/expanded notch views
├── CardStack.swift             # session cards (expanded + collapsed)
├── Timeline.swift              # task timeline with approval nodes
├── Components.swift            # progress ring, diff views, dot progress
├── Shapes.swift                # notch shape geometry
├── Settings.swift              # preferences UI + launch agent
├── Onboarding.swift            # first-launch setup wizard
├── Models.swift                # AgentSession, TaskItem, NotchState, pricing
├── ProviderCore.swift          # protocols, capabilities, provider catalog
├── ProviderManager.swift       # provider routing and lifecycle
├── ClaudeCodeBridge.swift      # Claude hooks, events, approvals
├── CodexProvider.swift         # Codex process discovery + monitoring
├── TranscriptReader.swift      # Claude transcript (.jsonl) parser
├── CodexTranscriptReader.swift # Codex transcript (.jsonl) parser
├── SessionHistory.swift        # past session scanning + resume
├── Shell.swift                 # process runner, pgrep, JSONL parsing
├── TerminalHelper.swift        # Terminal.app / iTerm2 AppleScript bridge
├── GitIntegration.swift        # branch, status, diff parsing
└── UpdateChecker.swift         # GitHub release polling
```

## Features at a Glance

| Feature | Claude | Codex |
|---------|:------:|:-----:|
| Live session monitoring | yes | yes |
| Real-time reasoning | yes | yes |
| Tool activity timeline | yes | yes |
| Live approval cards | yes | — |
| Hotkey approve/reject | yes | — |
| Token & cost tracking | yes | yes |
| Git branch & diff view | yes | yes |
| Session history & resume | yes | yes |
| Integration install/remove | yes | yes |
| CLAUDE.md / AGENTS.md editor | yes | yes |
| Desktop notifications | yes | yes |
| Multi-session support | yes | yes |

## FAQ

**Does it phone home?**
No. NotchBar is local-first. The only network call is checking GitHub releases for updates once a day.

**Does it work on external monitors?**
Yes. NotchBar creates a panel on every connected display. Screens without a notch get a pill-shaped overlay instead.

**What happens if NotchBar crashes or quits?**
Claude Code keeps working. The hook script detects NotchBar is gone and auto-approves everything — your agent is never stuck waiting.

**Does it work with other terminals?**
Terminal.app and iTerm2 are supported for input injection. Session monitoring works regardless of terminal.

## Contributing

Issues and PRs welcome at [github.com/lukataylo/NotchBar](https://github.com/lukataylo/NotchBar).

## Stability Notes

- The app now includes runtime exception logging in `~/Library/Logs/NotchBar/runtime.log`
- Claude hook generation correctly targets the renamed `NotchBar` process
- Update checks now point at the correct `NotchBar` GitHub repository
- The app bundle now declares Apple Events usage for Terminal/iTerm automation flows

## License

MIT — see [LICENSE](LICENSE).
