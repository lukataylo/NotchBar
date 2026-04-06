# Contributing to NotchBar

NotchBar is built for vibe coding. The entire plugin system was designed so you can add support for your favorite tool in under an hour — most of it spent deciding what icon to use.

## The Fastest Way to Contribute

### 1. Build a plugin

The best contribution is a new plugin. If you use a coding assistant or dev tool that NotchBar doesn't support yet, you can add it.

**What you need to know:**
- A plugin is one Swift file (~80-150 lines)
- No build system changes, no manifest files, no config
- You implement one protocol (`AgentProviderController`), return a descriptor, register one line

**Start here:**

```bash
# Clone and build
git clone https://github.com/lukataylo/NotchBar.git
cd NotchBar
swift build

# If you have Claude Code, use the built-in guide:
/create-plugin

# Or read it directly:
cat .claude/commands/create-plugin.md
```

**Plugin ideas we'd love to see:**
- **Aider** — open-source AI assistant, writes to `.aider.chat.history.md`
- **Windsurf/Cascade** — Codeium's editor with agent sessions
- **GitHub Copilot Chat** — VS Code copilot chat activity
- **CI Status** — poll `gh run list` for GitHub Actions status
- **Deploy Tracker** — Vercel/Railway/Fly deployment status
- **Docker Monitor** — running container health and logs
- **SSH Sessions** — remote server task monitoring

**Three patterns to choose from:**

| Pattern | Effort | Best for | Example |
|---------|--------|----------|---------|
| Process monitor | ~80 lines | CLI tools, builds, tests | `BuildMonitorProvider.swift` |
| Transcript monitor | ~150 lines | AI assistants with log files | `CodexProvider.swift` |
| Hook IPC | ~300 lines | Deep integration with approval flow | `ClaudeCodeBridge.swift` |

Most new plugins should start with the process monitor pattern. It's the simplest and covers the most tools.

### 2. Improve an existing plugin

Each plugin lives in a single file. Pick one and make it better:

- Better process detection heuristics
- Richer transcript parsing
- New session metadata extraction
- Smarter lifecycle detection

### 3. Fix a bug or improve the UI

The codebase is ~5k lines of Swift. No external dependencies. You can read the whole thing in an afternoon.

## Development Setup

```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Run
swift run NotchBar

# Build distributable app bundle
./scripts/build_app.sh

# Build DMG
./scripts/create_dmg.sh
```

**Requirements:** macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

## Project Structure

```
Sources/NotchBar/
├── main.swift                  # Entry point (7 lines)
├── Infrastructure.swift        # App delegate, panels, hotkeys, menu bar
├── Views.swift                 # Collapsed/expanded notch views
├── ApprovalOverlay.swift       # Doorbell approval UI
├── CardStack.swift             # Session cards
├── Timeline.swift              # Task timeline
├── Components.swift            # Shared UI components
├── Shapes.swift                # Notch geometry, icons
├── Settings.swift              # Settings UI + plugin store
├── Onboarding.swift            # First-launch wizard
├── Models.swift                # Data models (AgentSession, TaskItem, etc.)
├── ProviderCore.swift          # Plugin protocol + registry
├── ProviderManager.swift       # Plugin lifecycle + action routing
├── ClaudeCodeBridge.swift      # Claude Code plugin (stable)
├── CodexProvider.swift         # Codex plugin (beta)
├── CursorProvider.swift        # Cursor plugin (beta)
├── BuildMonitorProvider.swift  # Build monitor plugin (beta)
├── TestRunnerProvider.swift    # Test runner plugin (beta)
├── SocketServer.swift          # Unix domain socket IPC
├── TranscriptReader.swift      # Claude transcript parser
├── CodexTranscriptReader.swift # Codex transcript parser
├── Shell.swift                 # Process utilities
├── GitIntegration.swift        # Git status/diff
├── TerminalHelper.swift        # Terminal.app / iTerm2 bridge
├── SessionHistory.swift        # Past session scanning
└── UpdateChecker.swift         # GitHub release polling
```

## Code Style

- **No external dependencies.** If you need something, build it or use Apple frameworks.
- **One file per plugin.** The plugin should be self-contained.
- **Main thread for UI.** All `@Published` property updates must happen on `DispatchQueue.main`.
- **Fail-open for approvals.** If NotchBar can't respond, the agent should keep working.
- **No force unwraps.** Use optional chaining, `guard let`, or `??` defaults.
- **Descriptive but short.** Functions should be obvious from their name. Comments only where the *why* isn't clear.

## Submitting a PR

1. Fork the repo
2. Create a branch (`git checkout -b my-plugin`)
3. Make your changes
4. Build and verify (`swift build`)
5. Test manually — run `swift run NotchBar` and verify your plugin appears in Settings > Plugins
6. Push and open a PR

For plugin PRs, include:
- What tool/service it monitors
- How it detects sessions (pgrep, log files, etc.)
- A brief test plan (e.g. "run `cargo build`, verify session appears in notch")

## Vibe Coding Welcome

This project was built with AI coding assistants. We encourage contributions made the same way. Use Claude Code, Cursor, Copilot, Aider — whatever makes you productive. The `/create-plugin` command in Claude Code will walk you through building a plugin step by step.

If your AI assistant writes a NotchBar plugin to monitor itself, that's peak recursion and we love it.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
