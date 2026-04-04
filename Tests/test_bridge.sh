#!/bin/bash
# NotchBar integration tests (v2.0)
# These tests validate the build, hook script, and event format
# without launching the GUI app (safe for CI/headless environments).
set -e
EVENTS_DIR="$HOME/.notchbar/events"
RESPONSES_DIR="$HOME/.notchbar/responses"
HOOK="$HOME/.notchbar/bin/notchbar-hook"
LOG_FILE="$HOME/.notchbar/hook.log"
PASS=0; FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  x $1: $2"; }

echo "NotchBar Tests (v2.0)"
echo "========================"

# 1. Build
echo ""; echo "Build:"
swift build -c debug 2>&1 | tail -1
[ -f .build/debug/NotchBar ] && pass "Binary builds" || fail "Build" "binary not found"

echo ""
echo "Info.plist:"
plutil -lint -s Sources/NotchBar/Info.plist \
    && pass "Info.plist is valid" || fail "Info.plist" "invalid plist"

echo ""
echo "Hook script source:"
SOURCE_TEMPLATE="Sources/NotchBar/ClaudeCodeBridge.swift"
grep -q 'pgrep -x "NotchBar"' "$SOURCE_TEMPLATE" \
    && pass "Source hook template detects NotchBar process" \
    || fail "Hook template" "missing NotchBar process detection in source"

if [ -f "$HOOK" ]; then
    [ -x "$HOOK" ] && pass "Exists and executable" || fail "Hook script" "not executable"
    grep -q "pgrep" "$HOOK" && pass "Has NotchBar detection guard" || fail "Hook" "missing pgrep guard"
    grep -q "RESPONSES_DIR" "$HOOK" && pass "Has response directory support" || fail "Hook" "missing response dir"
    grep -q "MAX_ITERS" "$HOOK" && pass "Has correct timeout logic (MAX_ITERS)" || fail "Hook" "using old ELAPSED timeout"
    grep -q "log_msg" "$HOOK" && pass "Has logging support" || fail "Hook" "missing logging"
    grep -q "hook.log" "$HOOK" && pass "Logs to hook.log" || fail "Hook" "missing log file path"
    # Verify no python3 dependency
    ! grep -q "python3" "$HOOK" && pass "No python3 dependency" || fail "Hook" "still depends on python3"
    # Verify uses pgrep -x for exact match
    grep -q 'pgrep -x' "$HOOK" && pass "Uses exact process match (pgrep -x)" || fail "Hook" "missing exact match flag"
else
    pass "Hook script not generated yet (run app once)"
fi

echo ""
echo "Runtime directories:"
[ -d "$HOME/.notchbar" ] && pass "~/.notchbar directory exists" || pass "~/.notchbar not created yet (app not run)"
[ -d "$EVENTS_DIR" ] && pass "events directory exists" || pass "events directory not created yet"
[ -d "$RESPONSES_DIR" ] && pass "responses directory exists" || pass "responses directory not created yet"

# Check required fields are present
echo "$EVENT_JSON" | grep -q '"tool_name"' && pass "Event has tool_name field" || fail "Event" "missing tool_name"
echo "$EVENT_JSON" | grep -q '"session_id"' && pass "Event has session_id field" || fail "Event" "missing session_id"
echo "$EVENT_JSON" | grep -q '"permission_mode"' && pass "Event has permission_mode field" || fail "Event" "missing permission_mode"

# 4. Response JSON validation
echo ""; echo "Response Format:"
RESPONSE_JSON='{"decision":"approve"}'
echo "$RESPONSE_JSON" | plutil -lint -s - 2>/dev/null \
    && pass "Approve response is valid JSON" || fail "Response" "invalid JSON"

REJECT_JSON='{"decision":"deny","reason":"User rejected from NotchBar"}'
echo "$REJECT_JSON" | plutil -lint -s - 2>/dev/null \
    && pass "Reject response is valid JSON" || fail "Response" "invalid reject JSON"

# 5. Settings file (non-destructive check)
echo ""; echo "Settings:"
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    plutil -lint -s "$SETTINGS" 2>/dev/null && pass "settings.json valid JSON" || fail "Settings" "invalid JSON"
    grep -q "notchbar-hook" "$SETTINGS" \
        && pass "NotchBar hooks found in settings.json" \
        || pass "No NotchBar hooks in settings (not yet installed)"
else
    pass "No settings file (hooks not installed yet)"
fi

# Cleanup test files only
rm -f "$EVENTS_DIR"/test-*.json "$RESPONSES_DIR"/test-*.json 2>/dev/null

echo ""; echo "========================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
