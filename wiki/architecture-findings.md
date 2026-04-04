# NotchBar Architecture Findings

## Session Summary (2026-04-04)

Investigation into why NotchBar crashes Claude Code sessions and what architectural changes are needed to make approvals reliable.

## Current Architecture (File-Based IPC)

```
Claude Code
  |
  v
Hook script (bash, runs per tool call)
  |  writes JSON to ~/.notchbar/events/
  |  polls ~/.notchbar/responses/ for reply
  v
NotchBar (Swift app)
  |  DispatchSource watches events dir
  |  processEvents() on main thread
  |  handleEvent() updates UI + writes response file
  v
Hook script reads response, returns to Claude Code
```

### Problems Found

**1. DispatchSource latency (root cause of slowness)**
- DispatchSource on main queue coalesces filesystem events
- If main thread is busy (UI rendering, timer callbacks, git polling), event processing is delayed
- Measured: 2.5 seconds per tool call round-trip with NotchBar running
- Without NotchBar: 28ms per tool call

**2. macOS Automatic Termination (root cause of crashes)**
- NotchBar is LSUIElement (background app) with no visible windows
- macOS kills it thinking it's idle
- Hook script then blocks Claude Code for up to 5 seconds per tool call (pgrep interval)
- Fix: `ProcessInfo.processInfo.disableAutomaticTermination()`

**3. File-based IPC race conditions**
- Event file can be deleted before NotchBar reads it
- Response file can be written before hook starts polling
- Multiple rapid tool calls can overwhelm the DispatchSource
- `handledEvents` set accessed from multiple queues

**4. Hook script overhead**
- Each invocation spawns: bash, pgrep, grep, sed/awk, mkdir
- ~30ms baseline overhead per call even when auto-approving
- For 100 tool calls in a session: 3+ seconds of pure overhead

**5. Blocking approval design**
- Default settings: Bash/Agent tools require approval
- Claude Code uses Bash for almost everything
- Every Bash call blocks until user manually approves or 5-min timeout
- Users experience this as "Claude Code hangs when NotchBar is running"

### Current Workaround

Auto-approve tools directly in the bash hook script based on baked-in settings. Events sent to NotchBar in background for display only. This makes auto-approved tools fast (~30ms) but means NotchBar can't actually control approvals for those tools.

For tools requiring approval, the file polling loop still has the latency problem.

## Proposed Architecture: Unix Domain Socket IPC

Replace filesystem IPC with a Unix domain socket at `~/.notchbar/notchbar.sock`.

```
Claude Code
  |
  v
Hook script (bash)
  |  connects to ~/.notchbar/notchbar.sock
  |  sends event JSON
  |  blocks on recv (kernel-level, zero CPU)
  v
NotchBar (Swift)
  |  socket listener on background thread
  |  reads event, decides approve/reject
  |  sends response directly to socket
  v
Hook script reads response, returns to Claude Code
```

### Why This Fixes Everything

| Problem | File IPC | Socket IPC |
|---------|----------|------------|
| Latency | 50-2500ms (DispatchSource + polling) | <5ms (kernel notification) |
| CPU usage | Polling loop burns cycles | Blocking recv uses zero CPU |
| Race conditions | File read/write/delete races | Single bidirectional stream |
| NotchBar not running | 5s delay (pgrep interval) | Instant connection refused |
| Main thread blocking | Events queued behind UI work | Dedicated listener thread |

### Implementation Plan

**NotchBar side:**
1. On launch, create Unix domain socket at `~/.notchbar/notchbar.sock`
2. Listen for connections on a dedicated background thread
3. For each connection: read event JSON, decide action, send response JSON
4. Auto-approved tools: respond immediately on the socket thread (no main thread)
5. Tools needing approval: hold connection open, dispatch to main for UI, respond when user decides

**Hook script:**
```bash
#!/bin/bash
# Connect to NotchBar socket, send event, get response
SOCK="$HOME/.notchbar/notchbar.sock"
[ "$1" != "pre-tool-use" ] && { cat - | nc -U "$SOCK" >/dev/null 2>&1 & exit 0; }
# Pre-tool-use: need response
RESPONSE=$(cat - | nc -U "$SOCK" 2>/dev/null) || { echo '{"decision":"approve"}'; exit 0; }
echo "$RESPONSE"
```

The hook script becomes 5 lines. If NotchBar isn't running, `nc -U` fails instantly and we auto-approve. No pgrep, no polling, no file I/O.

**Key constraint:** The `nc` (netcat) command with `-U` flag for Unix sockets is available on macOS by default.

### Migration Path

1. Implement socket listener alongside existing file-based system
2. New hook script tries socket first, falls back to file-based
3. Once validated, remove file-based code

## Other Findings

### Code Signing
- Developer ID Application certificate requires private key from CSR generation
- CSR must be generated on the same Mac that will sign
- App-specific password stored in keychain as `notchbar-notarize`
- Team ID: `5QC5886P5V`
- Build scripts ready for signing at `scripts/build_app.sh` and `scripts/create_dmg.sh`

### Old Notchcode vs New NotchBar
- Old version at `/Users/lukadadiani/Documents/Notchcode` (named NotchClaude)
- Same file-based IPC architecture, same bugs, but lighter app = less main thread contention
- New version adds: multi-provider support, ProviderManager abstraction, Shell/TerminalHelper utilities
- The abstraction layers add main thread work, making the latency problem worse

### Settings Defaults
- Changed all auto-approve defaults to `true` (was: only reads)
- Users who want approval control can disable per-category in Settings
- Hook script bakes in the auto-approve list at generation time
- Changing settings requires NotchBar restart to regenerate hook script
