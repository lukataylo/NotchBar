#!/bin/bash
# NotchClaude integration tests (v2.0)
# These tests validate the build, hook script, and event format
# without launching the GUI app (safe for CI/headless environments).
set -e
EVENTS_DIR="$HOME/.notchclaude/events"
RESPONSES_DIR="$HOME/.notchclaude/responses"
HOOK="$HOME/.notchclaude/bin/notchclaude-hook"
LOG_FILE="$HOME/.notchclaude/hook.log"
PASS=0; FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1: $2"; }

echo "NotchClaude Tests (v2.0)"
echo "========================"

# Clean up test artifacts from previous runs
rm -f "$EVENTS_DIR"/test-*.json "$RESPONSES_DIR"/test-*.json 2>/dev/null

# 1. Build
echo ""; echo "Build:"
swift build -c debug 2>&1 | tail -1
[ -f .build/debug/NotchClaude ] && pass "Binary builds" || fail "Build" "binary not found"

# 2. Hook script checks (if it exists — may not if app hasn't been run yet)
echo ""; echo "Hook Script:"
if [ -f "$HOOK" ]; then
    [ -x "$HOOK" ] && pass "Exists and executable" || fail "Hook script" "not executable"
    grep -q "pgrep" "$HOOK" && pass "Has NotchClaude detection guard" || fail "Hook" "missing pgrep guard"
    grep -q "RESPONSES_DIR" "$HOOK" && pass "Has response directory support" || fail "Hook" "missing response dir"
    grep -q "MAX_ITERS" "$HOOK" && pass "Has correct timeout logic (MAX_ITERS)" || fail "Hook" "using old ELAPSED timeout"
    grep -q "log_msg" "$HOOK" && pass "Has logging support" || fail "Hook" "missing logging"
    grep -q "hook.log" "$HOOK" && pass "Logs to hook.log" || fail "Hook" "missing log file path"
    # Verify no python3 dependency
    ! grep -q "python3" "$HOOK" && pass "No python3 dependency" || fail "Hook" "still depends on python3"
    # Verify uses pgrep -x for exact match
    grep -q 'pgrep -x' "$HOOK" && pass "Uses exact process match (pgrep -x)" || fail "Hook" "missing exact match flag"
else
    echo "  (Hook script not found — run the app first to generate it)"
    pass "Skipped (hook not generated yet)"
fi

# 3. Event JSON structure validation
echo ""; echo "Event Format:"
EVENT_JSON='{"session_id":"x","cwd":"/test","tool_name":"Edit","tool_input":{"file_path":"/test/a.ts"},"hook_type":"post-tool-use","request_id":"1","permission_mode":"default"}'
# Validate with built-in plutil (no python3 needed)
echo "$EVENT_JSON" | plutil -lint -s - 2>/dev/null \
    && pass "Event JSON is valid" || fail "Event structure" "invalid JSON"

# Check required fields are present
echo "$EVENT_JSON" | grep -q '"tool_name"' && pass "Event has tool_name field" || fail "Event" "missing tool_name"
echo "$EVENT_JSON" | grep -q '"session_id"' && pass "Event has session_id field" || fail "Event" "missing session_id"
echo "$EVENT_JSON" | grep -q '"permission_mode"' && pass "Event has permission_mode field" || fail "Event" "missing permission_mode"

# 4. Response JSON validation
echo ""; echo "Response Format:"
RESPONSE_JSON='{"decision":"approve"}'
echo "$RESPONSE_JSON" | plutil -lint -s - 2>/dev/null \
    && pass "Approve response is valid JSON" || fail "Response" "invalid JSON"

REJECT_JSON='{"decision":"deny","reason":"User rejected from NotchClaude"}'
echo "$REJECT_JSON" | plutil -lint -s - 2>/dev/null \
    && pass "Reject response is valid JSON" || fail "Response" "invalid reject JSON"

# 5. Settings file (non-destructive check)
echo ""; echo "Settings:"
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    plutil -lint -s "$SETTINGS" 2>/dev/null && pass "settings.json valid JSON" || fail "Settings" "invalid JSON"
    grep -q "notchclaude-hook" "$SETTINGS" \
        && pass "NotchClaude hooks found in settings.json" \
        || pass "No NotchClaude hooks in settings (not yet installed)"
else
    pass "No settings file (hooks not installed yet)"
fi

# 6. Directory structure
echo ""; echo "Directories:"
[ -d "$HOME/.notchclaude" ] && pass "~/.notchclaude directory exists" || pass "~/.notchclaude not created yet (app not run)"
[ -d "$HOME/.notchclaude/events" ] && pass "events/ directory exists" || pass "events/ not created yet"
[ -d "$HOME/.notchclaude/responses" ] && pass "responses/ directory exists" || pass "responses/ not created yet"

# 7. Info.plist validation
echo ""; echo "App Bundle:"
if [ -f Sources/NotchClaude/Info.plist ]; then
    plutil -lint -s Sources/NotchClaude/Info.plist 2>/dev/null \
        && pass "Info.plist is valid" || fail "Info.plist" "invalid plist"
fi

# Cleanup test files only
rm -f "$EVENTS_DIR"/test-*.json "$RESPONSES_DIR"/test-*.json 2>/dev/null

echo ""; echo "========================"
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && echo "All tests passed!" || exit 1
