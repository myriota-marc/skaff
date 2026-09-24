#!/bin/sh
# Opt-in example, not installed by default. PreToolUse hook that forces a human permission
# prompt (permissionDecision "ask") before any write to an external system; reads pass silently.
# Adopt: copy to .claude/hooks/guard-writes.sh, edit the four patterns below, record the choice
# in an ADR, and register it in .claude/settings.json (see continuity-protocol.md "Opt-in guards").
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"

# Hosts whose REST calls count as external writes when they send data or a write method.
HOSTS='example\.atlassian\.net|api\.example\.com'
# CLI subcommands that write to an external system.
CLI_WRITES='(^|[;&|[:space:]])(forge[[:space:]]+(deploy|install|uninstall)|terraform[[:space:]]+apply|kubectl[[:space:]]+(apply|delete))([[:space:]]|$)'
# MCP servers to guard (tool names are mcp__<server>__<tool>), and the tool verbs that only read.
MCP_TOOLS='^mcp__.*[Aa]tlassian'
MCP_READS='^(get|search|lookup|fetch|list|read)'

in="$(cat)"
tool="$(printf '%s' "$in" | jq -r '.tool_name // empty')"
why=''
case "$tool" in
  Bash)
    cmd="$(printf '%s' "$in" | jq -r '.tool_input.command // empty')"
    if printf '%s' "$cmd" | grep -qE "$HOSTS" \
       && printf '%s' "$cmd" | grep -qE '(-X|--request)[[:space:]]*(POST|PUT|PATCH|DELETE)|(^|[[:space:]])(-d|--data[a-z-]*|-F|--form|-T)([[:space:]=]|$)|Invoke-(RestMethod|WebRequest).*-Method[[:space:]]+(Post|Put|Patch|Delete)'; then
      why="REST write"
    fi
    printf '%s' "$cmd" | grep -qE "$CLI_WRITES" && why="CLI write"
    ;;
  mcp__*)
    if printf '%s' "$tool" | grep -qE "$MCP_TOOLS" && ! printf '%s' "${tool##*__}" | grep -qE "$MCP_READS"; then
      why="MCP write ($tool)"
    fi ;;
esac
[ -n "$why" ] || exit 0
jq -n --arg r "guard-writes: $why. Confirm with the human via AskUserQuestion before approving." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"ask", permissionDecisionReason:$r}}'
exit 0
