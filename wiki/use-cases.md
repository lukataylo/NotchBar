# NotchBar Use Cases

A breakdown of how NotchBar fits into real-world AI-assisted development workflows.

---

## 1. Single Background Claude Code Terminal

**Scenario:** You have one Claude Code session running a long task (refactoring a module, writing tests, migrating a codebase) while you work in another app — browser, Figma, Slack, etc.

**Without NotchBar:** You constantly Cmd+Tab back to the terminal to check if Claude is still running, waiting for input, or finished. You miss approval prompts and Claude sits idle for minutes.

**With NotchBar:**
- The notch shows a live progress ring and status text — *Running*, *Waiting*, *Completed*
- Desktop notifications fire on completion or when Claude needs input
- Approval hotkeys (Cmd+Shift+Y / N) let you approve tool use without leaving your current app
- Cost and token counters keep you aware of spend in the background

**Key value:** Never lose time to an unnoticed idle agent.

---

## 2. Multiple Concurrent Claude Code Terminals

**Scenario:** You run 2-3 Claude Code sessions in parallel — one refactoring backend routes, one writing frontend tests, one updating docs. Each is in a different project directory or different terminal tab.

**Without NotchBar:** You juggle terminal windows, losing track of which session needs attention. An approval prompt in terminal 3 blocks progress while you're focused on terminal 1.

**With NotchBar:**
- Each session appears as a separate card with its own timeline, progress, and status
- The session picker rail (colored dots) gives instant visibility into all sessions at a glance
- The most urgent session auto-expands (approval-needed > waiting > running > idle)
- Hotkeys approve/reject the *currently focused* session's pending tool — no window switching needed
- Collapsed view shows per-session model, token counts, cost, and duration side by side

**Key value:** Manage parallel agents from one place without context-switching between terminals.

---

## 3. Claude Code + Codex Side-by-Side

**Scenario:** You use Claude Code for interactive coding tasks and OpenAI Codex for batch/sandboxed operations. Both are running simultaneously on different parts of the codebase.

**Without NotchBar:** Two completely separate tools with different UIs and no unified view. You check each terminal independently.

**With NotchBar:**
- Both providers appear as cards in the same panel — provider icon distinguishes them (sparkles vs terminal)
- Claude sessions show full approval controls; Codex sessions show monitoring-only (timeline, reasoning, tokens)
- The UI gracefully adapts based on each provider's capabilities — no fake controls for things Codex doesn't support
- Unified git status bar shows the shared repo state regardless of which agent is active

**Key value:** One dashboard for all your AI agents, regardless of provider.

---

## 4. Approval-Heavy Workflows

**Scenario:** You're running Claude Code with conservative permissions — no auto-approve on Bash or Edit. Every file write and shell command requires your explicit approval. This is common when working in production codebases, unfamiliar repos, or security-sensitive projects.

**Without NotchBar:** Claude stops and waits in the terminal. If you're in another window, you don't know it's waiting. You come back minutes later to find it's been idle the whole time.

**With NotchBar:**
- Approval cards appear instantly in the expanded panel with tool name, file path, command preview, and diff
- The notch pulses and shows "Approve?" status — visible even in collapsed mode
- Notification sound alerts you immediately
- Cmd+Shift+Y approves without touching the terminal — stay in your editor, browser, or meeting notes
- Configurable timeout (1-10 min or never) auto-approves if you don't respond, preventing permanent stalls
- Per-category auto-approve settings: auto-approve reads but manually approve writes and commands

**Key value:** Tight approval control without the productivity penalty of constant terminal-checking.

---

## 5. Fully Auto-Approved Background Operation

**Scenario:** You trust Claude with a well-scoped task — "run the full test suite and fix any failures" — and enable auto-approve on all tool categories. You want to walk away and come back to results.

**Without NotchBar:** You leave the terminal running and hope for the best. No visibility into progress, cost, or whether it went off the rails.

**With NotchBar:**
- Progress ring and task timeline show real-time tool activity even with no approvals needed
- Token and cost counters let you monitor spend — catch a runaway session before it burns through your API budget
- Claude's reasoning summaries show *what it's thinking* so you can spot if it's going down the wrong path
- Completion notification tells you exactly when it's done
- Git status bar shows how many files changed — quick sanity check before you review the diff
- Session history lets you review past completed sessions and their outcomes

**Key value:** Fire-and-forget with a safety net — always know what your agent is doing and spending.

---

## 6. Pair Programming with Claude (Interactive)

**Scenario:** You're actively coding alongside Claude — asking it to implement a feature, reviewing its output, iterating. You're frequently switching between your editor and the terminal.

**Without NotchBar:** The terminal is your only window into Claude's state. You read raw tool call output and scroll through verbose transcripts.

**With NotchBar:**
- The expanded panel provides a clean timeline of every tool call with durations and diffs
- Inline diff viewer shows exactly what Claude changed without running `git diff` manually
- Claude's reasoning block shows its latest thinking — useful for understanding *why* it made a choice
- Quick glance at the notch tells you if Claude is still working or waiting for your next message

**Key value:** A structured, visual companion to the terminal's raw output.

---

## 7. Multi-Screen / External Display Setup

**Scenario:** You have a MacBook connected to one or more external monitors. Your terminal is on one screen, your editor on another.

**With NotchBar:**
- The notch bar renders on every connected screen — always visible regardless of which display you're focused on
- On displays without a physical notch, it renders as a rounded pill shape at the top center
- Hotkeys are global — work from any screen, any app

**Key value:** Agent status follows you across screens.

---

## 8. Long-Running Migrations or Refactors

**Scenario:** You kick off a large task — "migrate all API endpoints from REST to GraphQL" or "convert the entire codebase from JavaScript to TypeScript." This could run for 30+ minutes with hundreds of tool calls.

**With NotchBar:**
- Task timeline caps at 12 visible items (FIFO) so the UI stays responsive even on huge sessions
- Cost tracking shows cumulative spend — essential for long sessions that could hit budget limits
- Duration counter shows elapsed time in a human-friendly format (seconds → minutes → hours)
- Session persists across NotchBar restarts — reconnects to running Claude processes via `pgrep`
- Completion notification means you can work on something else entirely and get called back

**Key value:** Confidence to let long tasks run without anxiety about cost or progress.

---

## 9. Onboarding / First-Time Setup

**Scenario:** You just installed NotchBar and want to connect it to your existing Claude Code workflow.

**Flow:**
1. Launch NotchBar — onboarding screen appears
2. Click "Install Integration" — NotchBar writes hook entries into `~/.claude/settings.json`
3. A hook script is placed at `~/.notchbar/bin/notchbar-hook`
4. Start any Claude Code session — NotchBar auto-detects it within 5 seconds
5. Configure auto-approve preferences in Settings (Cmd+,)

**For Codex:** Similar flow — NotchBar installs a managed profile in `~/.codex/config.toml`.

**Key value:** One-click setup, non-destructive (preserves existing hooks/config).

---

## Summary Matrix

| Workflow | Sessions | Approvals | Key Benefit |
|----------|----------|-----------|-------------|
| Single background terminal | 1 | Few | Never miss a prompt |
| Multiple concurrent terminals | 2-5 | Mixed | Unified dashboard |
| Claude + Codex | 2+ | Claude only | Cross-provider visibility |
| Approval-heavy | 1+ | Many | Hotkey approve from anywhere |
| Fully auto-approved | 1+ | None | Cost/progress monitoring |
| Interactive pair programming | 1 | Few | Visual timeline + diffs |
| Multi-screen | 1+ | Any | Status on every display |
| Long-running tasks | 1 | Varies | Confidence to walk away |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+C | Toggle panel (expand/collapse) |
| Cmd+Shift+Y | Approve pending tool |
| Cmd+Shift+N | Reject pending tool |
| Cmd+Shift+] | Next session |
| Cmd+Shift+[ | Previous session |
| Cmd+, | Open Settings |
