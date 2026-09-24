#!/bin/sh
# One-time setup per clone: versioned git hooks, pinned tools, Vale packages.
set -eu
. "$(dirname "$0")/lib.sh"
cd "$ROOT"
git config core.hooksPath .githooks
git config core.autocrlf false
ver() {
  case "$1" in
    vale) vale --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' ;;
    jq) jq --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' ;;
    gitleaks) gitleaks version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' ;;
  esac
}
fail=0
while read -r tool want; do
  [ -n "$tool" ] || continue
  if ! command -v "$tool" >/dev/null 2>&1; then echo "missing: $tool $want (winget, brew or asdf)"; fail=1; continue; fi
  have="$(ver "$tool")"
  [ "$have" = "$want" ] || { echo "version mismatch: $tool have $have want $want"; fail=1; }
done < .tool-versions
[ $fail -eq 0 ] || exit 1
vale sync >/dev/null
echo "bootstrap: hooks at .githooks, tools match .tool-versions, Vale packages synced"
