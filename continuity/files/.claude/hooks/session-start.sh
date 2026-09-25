#!/bin/sh
# SessionStart: the whole cold start, at most 40 lines on stdout.
# Highest-value sections print first so the 40-line cap only ever trims history.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
cd "$ROOT" || exit 0
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "== branch: $(git symbolic-ref --short HEAD 2>/dev/null || echo detached)"
  echo "== stale docs"
  find docs -name '*.md' 2>/dev/null | while read -r f; do
    s="$(frontmatter "$f" | sed -n 's/^stale_after: *//p' | tr -d '"')"
    [ -n "$s" ] && ! expr "$now" \< "$s" >/dev/null && echo "STALE $f (stale_after $s)"
  done
  echo "== open gates"
  state_items | grep -vE 'status: done' | while read -r l; do
    id="$(item_field "$l" id)"; [ -f ".gates/$id.json" ] || printf '%s (%s)\n' "$id" "$(item_field "$l" status)"
  done
  echo "== docs/STATE.md (done items and verified list omitted)"
  frontmatter docs/STATE.md 2>/dev/null | grep -vE '^(type|description|generated|verified):|status: done'
  echo "== ADRs (last 10)"
  grep -E '^- \[' docs/decisions/index.md 2>/dev/null | tail -n 10
  echo "== git log"
  git log --oneline -5 2>/dev/null
} | head -n 40
exit 0
