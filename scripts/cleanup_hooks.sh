#!/bin/bash
set -euo pipefail

echo "==> NotchBar Hook Cleanup"
echo ""

SETTINGS="$HOME/.claude/settings.json"
NOTCHBAR_DIR="$HOME/.notchbar"
NOTCHCLAUDE_DIR="$HOME/.notchclaude"

# 1. Remove stale notchclaude entries from settings.json
if [ -f "$SETTINGS" ]; then
    echo "Checking $SETTINGS for stale hooks..."

    if grep -q "notchclaude-hook" "$SETTINGS" 2>/dev/null; then
        echo "  Found stale notchclaude-hook entries, removing..."
        python3 -c "
import json, sys
with open('$SETTINGS') as f:
    settings = json.load(f)
hooks = settings.get('hooks', {})
for key in list(hooks.keys()):
    if isinstance(hooks[key], list):
        hooks[key] = [e for e in hooks[key] if not any('notchclaude-hook' in h.get('command','') for h in e.get('hooks',[]))]
        if not hooks[key]:
            del hooks[key]
if not hooks:
    settings.pop('hooks', None)
else:
    settings['hooks'] = hooks
with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
print('  Removed notchclaude-hook entries.')
"
    else
        echo "  No stale notchclaude-hook entries found."
    fi

    # Verify notchbar hooks are present and valid
    if grep -q "notchbar-hook" "$SETTINGS" 2>/dev/null; then
        echo "  NotchBar hooks are installed."
    else
        echo "  WARNING: No notchbar-hook entries found. Launch NotchBar to reinstall hooks."
    fi
else
    echo "  No settings.json found at $SETTINGS"
fi

echo ""

# 2. Clean up old notchclaude directory
if [ -d "$NOTCHCLAUDE_DIR" ]; then
    echo "Removing stale ~/.notchclaude directory..."
    rm -rf "$NOTCHCLAUDE_DIR"
    echo "  Removed."
else
    echo "No stale ~/.notchclaude directory found."
fi

echo ""

# 3. Clean up stale event/response files
if [ -d "$NOTCHBAR_DIR/events" ]; then
    STALE_EVENTS=$(find "$NOTCHBAR_DIR/events" -name "*.json" -mmin +5 2>/dev/null | wc -l | tr -d ' ')
    if [ "$STALE_EVENTS" -gt 0 ]; then
        echo "Removing $STALE_EVENTS stale event files (older than 5 min)..."
        find "$NOTCHBAR_DIR/events" -name "*.json" -mmin +5 -delete 2>/dev/null
        echo "  Removed."
    else
        echo "No stale event files."
    fi
fi

if [ -d "$NOTCHBAR_DIR/responses" ]; then
    STALE_RESPONSES=$(find "$NOTCHBAR_DIR/responses" -name "*.json" -mmin +5 2>/dev/null | wc -l | tr -d ' ')
    if [ "$STALE_RESPONSES" -gt 0 ]; then
        echo "Removing $STALE_RESPONSES stale response files (older than 5 min)..."
        find "$NOTCHBAR_DIR/responses" -name "*.json" -mmin +5 -delete 2>/dev/null
        echo "  Removed."
    else
        echo "No stale response files."
    fi
fi

echo ""

# 4. Truncate hook log if it's large
if [ -f "$NOTCHBAR_DIR/hook.log" ]; then
    LOG_SIZE=$(stat -f%z "$NOTCHBAR_DIR/hook.log" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 1048576 ]; then
        echo "Hook log is $(( LOG_SIZE / 1024 ))KB, truncating to last 1000 lines..."
        tail -1000 "$NOTCHBAR_DIR/hook.log" > "$NOTCHBAR_DIR/hook.log.tmp"
        mv "$NOTCHBAR_DIR/hook.log.tmp" "$NOTCHBAR_DIR/hook.log"
        echo "  Truncated."
    else
        echo "Hook log size OK ($(( LOG_SIZE / 1024 ))KB)."
    fi
fi

echo ""

# 5. Verify hook script is executable and correct
HOOK_SCRIPT="$NOTCHBAR_DIR/bin/notchbar-hook"
if [ -f "$HOOK_SCRIPT" ]; then
    if [ -x "$HOOK_SCRIPT" ]; then
        echo "Hook script is present and executable."
    else
        echo "WARNING: Hook script exists but is not executable. Fixing..."
        chmod 755 "$HOOK_SCRIPT"
        echo "  Fixed."
    fi

    # Test the hook script with a sample input
    RESULT=$(echo '{"session_id":"test","tool_name":"Read"}' | "$HOOK_SCRIPT" pre-tool-use 2>/dev/null)
    if echo "$RESULT" | grep -q '"decision"' 2>/dev/null; then
        echo "Hook script test: PASS (returned valid response)"
    else
        echo "WARNING: Hook script test returned unexpected output: $RESULT"
        echo "  Re-launch NotchBar to regenerate the hook script."
    fi
else
    echo "WARNING: Hook script not found at $HOOK_SCRIPT"
    echo "  Launch NotchBar to generate it."
fi

echo ""

# 6. Show current hook configuration
echo "==> Current hook configuration in settings.json:"
if [ -f "$SETTINGS" ]; then
    python3 -c "
import json
with open('$SETTINGS') as f:
    settings = json.load(f)
hooks = settings.get('hooks', {})
if not hooks:
    print('  No hooks configured.')
else:
    for key, entries in hooks.items():
        for e in entries:
            for h in e.get('hooks', []):
                cmd = h.get('command', 'N/A')
                print(f'  {key}: {cmd}')
"
fi

echo ""
echo "==> Cleanup complete."
