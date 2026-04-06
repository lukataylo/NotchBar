# Installing NotchBar

## Recommended

Download the latest `.dmg` from [GitHub Releases](https://github.com/lukataylo/NotchBar/releases).

1. Open the DMG
2. Drag `NotchBar.app` into Applications
3. Launch NotchBar

Because current builds are unsigned, macOS may warn on first launch. Right-click the app and choose `Open`, or go to `System Settings > Privacy & Security > Open Anyway`.

## From Source

```bash
git clone https://github.com/lukataylo/NotchBar.git
cd NotchBar
swift build
swift run NotchBar
```

**Requirements:** macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

## Build a DMG

```bash
./scripts/create_dmg.sh
```

Produces `dist/NotchBar.app` and `dist/NotchBar-<version>.dmg`.

## First-Launch Permissions

NotchBar can monitor sessions without extra permissions, but some features need macOS approval:

| Permission | Required for |
|-----------|-------------|
| Accessibility | Sending input to Terminal/iTerm |
| Automation | Controlling Terminal/iTerm for resume/input |
| Notifications | Approval and completion alerts (optional) |

## Plugin Setup

After launching, open Settings (menu bar icon > Settings, or `Cmd+,`) and go to the **Plugins** tab.

Each plugin can be enabled/disabled independently. For plugins that need a connection:

- **Claude Code**: Click Configure > Connect to add hook entries to `~/.claude/settings.json`
- **Codex** (disabled by default): Enable it first, then Configure > Connect to add a managed profile to `~/.codex/config.toml`
- **Conflict Detector**: Click Configure > Set Up Server to install the MCP coordination server

All auto-approve settings are off by default — you choose what your agent can do without asking. Your code, your rules.

## Troubleshooting

**App won't open:** Right-click > Open on first launch. macOS is just being protective. Check System Settings > Privacy & Security.

**Swift missing:** Install Xcode Command Line Tools: `xcode-select --install`

**Nothing happens when Claude runs:** Make sure you've connected the Claude Code plugin (Settings > Plugins > Claude Code > Configure > Connect). No connection = no party.

**Approvals always auto-approve:** All auto-approve is off by default now. If you turned them on and forgot, check Settings > Plugins > Claude Code > Configure > Auto-Approve Rules.

**Terminal input doesn't work:** Grant Accessibility and Automation permissions for NotchBar in macOS Privacy settings.
