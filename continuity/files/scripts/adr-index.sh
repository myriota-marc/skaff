#!/bin/sh
# Generate docs/decisions/index.md. --check: exit 1 if the committed index is stale.
set -eu
. "$(dirname "$0")/lib.sh"
dir="$ROOT/docs/decisions"
gen() {
  printf -- '---\nokf_version: "0.2"\n---\n'
  sup=''
  for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$f" ] || continue
    n="$(basename "$f" | cut -c1-4)"
    for s in $(frontmatter "$f" | sed -n 's/^supersedes: *//p' | grep -oE '[0-9]+'); do
      sup="$sup $(printf '%04d' "$s"):$n"
    done
  done
  for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; n="$(printf '%s' "$b" | cut -c1-4)"
    t="$(frontmatter "$f" | sed -n 's/^title: *//p' | tr -d '"' | sed -E 's/^[0-9]{4}: *//')"
    st="$(frontmatter "$f" | sed -n 's/^status: *//p')"
    by="$(printf '%s\n' $sup | sed -n "s/^$n://p" | tail -1)"
    [ -n "$by" ] && st="superseded by $by"
    printf -- '- [%s](%s): %s (%s)\n' "$n" "$b" "$t" "$st"
  done
}
if [ "${1:-}" = "--check" ]; then
  gen | cmp -s - "$dir/index.md" || { echo "docs/decisions/index.md is stale: run scripts/adr-index.sh" >&2; exit 1; }
else
  gen > "$dir/index.md"
fi
