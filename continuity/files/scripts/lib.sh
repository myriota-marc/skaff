# Shared helpers for continuity scripts and hooks. POSIX sh. Source, do not run.
# Rules: .claude/conventions/continuity-protocol.md
# ENFORCEMENT: fail-closed blocks; warn-only prints and exits 0. Override with CONTINUITY_ENFORCEMENT.
ENFORCEMENT="${CONTINUITY_ENFORCEMENT:-fail-closed}"
# HUMAN: actor id recorded in human gate evidence. Set by the Skaff installer; override with CONTINUITY_HUMAN.
HUMAN="${CONTINUITY_HUMAN:-@@CONTINUITY_HUMAN@@}"
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$(printf '%s' "$ROOT" | tr '\\' '/')"
# Root Markdown files outside Vale and OKF scope. Override with CONTINUITY_EXCLUDE_ROOT_MD.
EXCLUDE_ROOT_MD="${CONTINUITY_EXCLUDE_ROOT_MD:-CLAUDE.md AGENTS.md GEMINI.md}"

# block <code> <message...>: print up to 20 lines to stderr, exit per ENFORCEMENT.
block() {
  code="$1"; shift
  printf '%s\n' "$@" | head -n 20 >&2
  [ "$ENFORCEMENT" = "warn-only" ] && exit 0
  exit "$code"
}

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  block 2 "continuity: '$1' not found. Install: $2 (pinned in .tool-versions), then run scripts/bootstrap.sh"
}

# relpath <path>: path relative to ROOT, forward slashes. Handles C:\ , C:/ and /c/ forms.
norm() { printf '%s' "$1" | tr '\\' '/' | sed -E 's#^/([a-zA-Z])/#\1:/#'; }
relpath() {
  p="$(norm "$1")"; r="$(norm "$ROOT")"
  lp="$(printf '%s' "$p" | tr 'A-Z' 'a-z')"; lr="$(printf '%s' "$r" | tr 'A-Z' 'a-z')"
  case "$lp" in "$lr"/*) printf '%s' "$p" | cut -c "$(( ${#r} + 2 ))-" ;; *) printf '%s' "$p" ;; esac
}

# in_scope <relpath>: Vale and OKF scope: docs/** and root *.md minus EXCLUDE_ROOT_MD.
in_scope() {
  case "$1" in
    *.md) ;; *) return 1 ;;
  esac
  case "$1" in
    docs/*) return 0 ;;
    */*) return 1 ;;
  esac
  for x in $EXCLUDE_ROOT_MD; do [ "$1" = "$x" ] && return 1; done
  return 0
}

# frontmatter <file>: print YAML front matter body (between first two --- lines).
frontmatter() { awk 'NR==1&&$0!="---"{exit} NR==1{next} $0=="---"{exit} {print}' "$1"; }

# okf_check <relpath> <file>: print missing keys, return 1 if any.
okf_check() {
  case "$1" in
    docs/*) ;; *) return 0 ;;
  esac
  case "$1" in
    */index.md|*/log.md|docs/index.md|docs/log.md) keys='okf_version' ;;
    docs/decisions/[0-9][0-9][0-9][0-9]-*) keys='type title description status date supersedes' ;;
    *) keys='type title description status updated stale_after' ;;
  esac
  fm="$(frontmatter "$2")"; bad=0
  for k in $keys; do
    printf '%s\n' "$fm" | grep -q "^$k:" || { echo "OKF: $1 missing front matter key '$k'"; bad=1; }
  done
  return $bad
}

# state_items: print next_actions lines from docs/STATE.md front matter.
state_items() { [ -f "$ROOT/docs/STATE.md" ] && frontmatter "$ROOT/docs/STATE.md" | sed -n '/^next_actions:/,$p' | grep -E '^\s*- \{id: ' ; }
item_field() { printf '%s' "$1" | sed -nE "s/.*[{ ,]$2: (\"[^\"]*\"|[^,}]*).*/\1/p" | tr -d '"'; }
