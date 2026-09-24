#!/bin/sh
# Stop: refuse to stop while next_actions has open items. At most 2 blocks per session.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"
in="$(cat)"
[ "$(printf '%s' "$in" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
open="$(state_items | grep -E 'status: open' | while read -r l; do printf '%s: %s\n' "$(item_field "$l" id)" "$(item_field "$l" do)"; done)"
[ -n "$open" ] || exit 0
sid="$(printf '%s' "$in" | jq -r '.session_id // "none"')"
mkdir -p "$ROOT/.claude/.cache"; c="$ROOT/.claude/.cache/stop-$sid"
n="$(cat "$c" 2>/dev/null || echo 0)"
[ "$n" -ge 2 ] && exit 0
echo $((n + 1)) > "$c"
block 2 "stop-check: docs/STATE.md has open next_actions. Continue, or set status awaiting/blocked and name the blocker:" "$open"
