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

Each plugin can be enabled/disabled independently. For plugins that need integration:

- **Claude Code**: Click Configure > Install to add hook entries to `~/.claude/settings.json`
- **Codex**: Click Configure > Install to add a managed profile to `~/.codex/config.toml`
- **Cursor, Build Monitor, Test Runner**: No setup needed — they detect running processes automatically

## Troubleshooting

**App won't open:** Right-click > Open on first launch. Check System Settings > Privacy & Security.

**Swift missing:** Install Xcode Command Line Tools: `xcode-select --install`

**Approvals always auto-approve:** Make sure NotchBar is running. Check the Claude plugin's Configure panel for your approval rules.

**Terminal input doesn't work:** Grant Accessibility and Automation permissions for NotchBar in macOS Privacy settings.
