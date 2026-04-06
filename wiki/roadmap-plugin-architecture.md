# Roadmap: JSON-over-Socket Plugin Architecture

## Overview

Transform NotchBar from a single-purpose agent dashboard into a **persistent ambient display** with a plugin system. Plugins are external processes that push JSON state to NotchBar via Unix sockets. NotchBar renders plugin output through a standard card layout with typed sections.

## Design: JSON-over-Socket (Option A)

**Why this approach:**
- Matches the existing socket IPC pattern (hook scripts already work this way)
- Any language — Python, Node, Bash, a Claude skill script
- Crash isolation — plugin crashes don't take down NotchBar
- Hot reload — restart a plugin without restarting NotchBar
- No Swift/Xcode required for plugin authors

## Plugin Directory Structure

```
~/.notchbar/plugins/
├── conflict-monitor/
│   ├── plugin.json          # manifest: name, type, card schema
│   └── run.sh               # entry point (any language)
├── ci-status/
│   └── plugin.json
└── pomodoro/
    └── plugin.json
```

## Manifest Format

```json
{
  "id": "conflict-monitor",
  "name": "Conflict Monitor",
  "version": "1.0",
  "type": "card",
  "socket": "~/.notchbar/plugins/conflict-monitor/plugin.sock",
  "capabilities": ["card", "badge", "collapsed-status"],
  "schema": {
    "sections": ["header", "list", "actions"]
  }
}
```

## Card Schema — Section Types

| Section Type | Renders As |
|---|---|
| `header` | Title + icon + status badge |
| `list` | Rows with label, value, color, icon |
| `key-value` | Compact key-value pairs |
| `actions` | Buttons that send events back to the plugin |
| `progress` | Progress bar/ring |
| `alert` | Colored banner (like the context warning) |
| `text` | Markdown-ish block |

## Plugin Output Protocol

Plugin pushes JSON lines to its socket. NotchBar renders the latest state.

```json
{
  "card": {
    "header": { "title": "2 Conflicts", "icon": "exclamationmark.triangle.fill", "color": "orange" },
    "sections": [
      {
        "type": "list",
        "items": [
          {
            "icon": "doc.fill",
            "label": "src/Models.swift",
            "value": "backend + frontend sessions",
            "color": "red",
            "actions": [{ "id": "show-diff", "label": "Diff" }]
          }
        ]
      },
      {
        "type": "actions",
        "items": [
          { "id": "pause-newer", "label": "Pause Newer Session", "style": "warning" },
          { "id": "dismiss", "label": "Dismiss", "style": "secondary" }
        ]
      }
    ]
  },
  "badge": { "count": 2, "color": "orange" },
  "collapsed": "2 conflicts"
}
```

## Internal Architecture Changes

1. **PluginProtocol.swift** — protocol + manifest model + JSON card schema types
2. **PluginManager.swift** — discovery, lifecycle, socket relay
3. **PluginCardRenderer.swift** — generic SwiftUI view that renders card JSON
4. **PluginSession adapter** — makes plugin cards appear in the existing card stack

## First Plugin: Conflict Monitor

Watches git state and agent activity across sessions to detect:
- File-level conflicts — two sessions have pending changes to the same file
- Branch conflicts — two sessions on branches touching overlapping files
- Lock contention — one session writing to a file another is reading
- Merge conflict detection — proactive check against main

Resolution actions:
- Pause a session (reject pending approvals + flag)
- Show diff of what both sessions changed
- Queue sessions (hold approvals on one until the other finishes)

Implementation: ~200 lines of Swift or Python reading NotchBar socket events + git commands.

## Other Plugin Ideas

- **CI/CD status** — poll GitHub Actions, show build status per branch
- **Pomodoro timer** — work/break timer in the notch
- **System monitor** — CPU/memory/disk in the notch
- **Slack/notifications** — surface messages from specific channels
- **Deploy tracker** — show production deploy status
