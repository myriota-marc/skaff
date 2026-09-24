#!/usr/bin/env bash
# Deploys the Claude agent scaffold into a target project directory.
#
# Usage:
#   ./install.sh <NewProjectDir> [--pack <pack>[@<version>]] [--force]
#
# Arguments:
#   NewProjectDir   Absolute or relative path to the target project directory.
#                   Created if it does not exist.
#
# Options:
#   --pack <ref>          Pack and optional version. Default: csharp@latest.
#                         Examples: --pack csharp, --pack appsheet@v1, --pack python@v2.
#   --force               Overwrite existing files. Without this, existing files are
#                         skipped and reported.
#   --allow-pack-switch   Proceed when the target's recorded .claude/.pack names a
#                         different pack than --pack. Without this, installing a
#                         different pack over an existing install is refused after
#                         listing the files that would be orphaned. Re-installing the
#                         same pack (any version) is never a switch.
#   --no-continuity       Skip the continuity layer (continuity/ in this repo: git and
#                         Claude Code hooks, gate scripts, Vale, docs/STATE.md).
#   --human <id>          Actor id for human gate evidence, e.g. human:jdoe.
#                         Default: human:<local part of git config user.email>.
#   --purpose <text>      One sentence for docs/STATE.md purpose.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <NewProjectDir> [--pack <pack>[@<version>]] [--force]

Deploys the Claude agent scaffold into <NewProjectDir>.

Options:
  --pack <ref>          Pack and optional version (default: csharp). e.g. appsheet@v1
  --force               Overwrite existing files in the target.
  --allow-pack-switch   Proceed when the target was installed with a different pack.
  --no-continuity       Skip the continuity layer.
  --human <id>          Actor id for human gate evidence (default from git user.email).
  --purpose <text>      One sentence for docs/STATE.md purpose.
  -h, --help            Show this help and exit.
EOF
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

new_project_dir="$1"
shift
force=0
allow_pack_switch=0
pack_ref="csharp"
continuity=1
human=""
purpose=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --allow-pack-switch) allow_pack_switch=1 ;;
    --pack)
      shift
      if [ "$#" -lt 1 ]; then
        echo "--pack requires an argument" >&2; exit 1
      fi
      pack_ref="$1"
      ;;
    --no-continuity) continuity=0 ;;
    --human|--purpose)
      opt="$1"; shift
      if [ "$#" -lt 1 ]; then
        echo "$opt requires an argument" >&2; exit 1
      fi
      if [ "$opt" = "--human" ]; then human="$1"; else purpose="$1"; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# Parse pack@version. Default version is 'latest' which resolves to the highest
# numeric v<N> directory present under packs/<pack>/.
if [[ "$pack_ref" == *"@"* ]]; then
  pack_name="${pack_ref%@*}"
  pack_version="${pack_ref#*@}"
else
  pack_name="$pack_ref"
  pack_version="latest"
fi

script_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source_root="$script_path"
common_root="$source_root/common"
pack_dir="$source_root/packs/$pack_name"

if [ ! -d "$common_root" ]; then
  echo "Source layout not found. Expected common/ at $source_root" >&2
  exit 1
fi

if [ ! -d "$pack_dir" ]; then
  echo "Unknown pack: $pack_name. Available:" >&2
  ls "$source_root/packs" 2>/dev/null | grep -v '^README\|^SHARED\|\.md$' >&2 || true
  exit 1
fi

# Resolve version.
if [ "$pack_version" = "latest" ]; then
  pack_version="$(ls -1 "$pack_dir" 2>/dev/null | grep -E '^v[0-9]+$' | sort -V | tail -1 || true)"
  if [ -z "$pack_version" ]; then
    echo "Pack '$pack_name' has no installable versions yet. See packs/$pack_name/PACK.md" >&2
    exit 1
  fi
fi

pack_version_dir="$pack_dir/$pack_version"
if [ ! -d "$pack_version_dir" ]; then
  echo "Unknown version '$pack_version' for pack '$pack_name'. Available:" >&2
  ls -1 "$pack_dir" 2>/dev/null | grep -E '^v[0-9]+$' >&2 || true
  exit 1
fi

claude_template_rel="do-work/templates/CLAUDE.md.template"
if [ ! -f "$pack_version_dir/$claude_template_rel" ]; then
  echo "Pack '$pack_name@$pack_version' is missing required $claude_template_rel" >&2
  exit 1
fi

if [ ! -d "$new_project_dir" ]; then
  echo "Creating target directory: $new_project_dir"
  mkdir -p "$new_project_dir"
fi

target="$(cd -- "$new_project_dir" >/dev/null 2>&1 && pwd)"

# Guard against pack mixing. The installer never removes files, so replacing
# an installed pack with a different one orphans the first pack's
# uniquely-named agents (still discoverable and spawnable by Claude Code) and
# silently swaps same-named agents (ratchet.md, reviewer.md, git-workflow.md,
# do-work-run) between incompatible toolchains and ratchet dimension sets.
existing_pack_file="$target/.claude/.pack"
if [ -f "$existing_pack_file" ]; then
  existing_pack_name="$(grep -E '^pack:' "$existing_pack_file" | head -1 | sed -E 's/^pack:[[:space:]]*//')"
  existing_pack_version="$(grep -E '^version:' "$existing_pack_file" | head -1 | sed -E 's/^version:[[:space:]]*//')"

  if [ -n "$existing_pack_name" ] && [ "$existing_pack_name" != "$pack_name" ]; then
    old_pack_version_dir="$source_root/packs/$existing_pack_name/$existing_pack_version"
    orphaned_list=()
    if [ -d "$old_pack_version_dir" ]; then
      while IFS= read -r -d '' f; do
        rel="${f#"$old_pack_version_dir"/}"
        if [ ! -e "$pack_version_dir/$rel" ]; then
          orphaned_list+=("$rel")
        fi
      done < <(find "$old_pack_version_dir" -type f -print0)
    fi

    if [ "$allow_pack_switch" -eq 0 ]; then
      echo "Target was installed with pack '$existing_pack_name@$existing_pack_version'. Requested pack is '$pack_name@$pack_version'." >&2
      echo "Refusing: installing a different pack over an existing install orphans the previous pack's files - Claude Code still discovers and can spawn orphaned agents by their frontmatter 'name:', and same-named agents (ratchet.md, reviewer.md, git-workflow.md, the do-work-run command) get silently swapped between incompatible toolchains and ratchet dimension sets." >&2
      echo >&2
      if [ "${#orphaned_list[@]}" -gt 0 ]; then
        echo "${#orphaned_list[@]} file(s) unique to '$existing_pack_name@$existing_pack_version' would be orphaned:" >&2
        for f in "${orphaned_list[@]}"; do
          echo "  - $f" >&2
        done
      else
        echo "Could not enumerate the previous pack's overlay - packs/$existing_pack_name/$existing_pack_version is no longer present in this scaffold checkout." >&2
      fi
      echo >&2
      echo "Re-run with --allow-pack-switch to proceed anyway." >&2
      exit 1
    fi

    echo "Switching pack: '$existing_pack_name@$existing_pack_version' -> '$pack_name@$pack_version' (--allow-pack-switch supplied)."
    if [ "${#orphaned_list[@]}" -gt 0 ]; then
      echo "${#orphaned_list[@]} file(s) unique to '$existing_pack_name@$existing_pack_version' will be orphaned:"
      for f in "${orphaned_list[@]}"; do
        echo "  - $f"
      done
    fi
    echo
  fi
fi

echo "Source: $source_root"
echo "Pack:   $pack_name@$pack_version"
echo "Target: $target"
echo

copied=0
skipped=0
copied_list=()
skipped_list=()

# copy_tree <source_root> - walks a source tree and copies files into the
# target, preserving relative paths. The CLAUDE.md.template special-case is
# skipped here; handled after both trees are copied.
copy_tree() {
  local src="$1"
  while IFS= read -r -d '' file; do
    local rel="${file#"$src"/}"

    # Skip the special-cased template - it installs to <target>/CLAUDE.md below.
    if [ "$rel" = "$claude_template_rel" ]; then
      continue
    fi

    local dest="$target/$rel"
    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ] && [ "$force" -eq 0 ]; then
      skipped=$((skipped + 1))
      skipped_list+=("$rel")
      continue
    fi

    cp "$file" "$dest"
    copied=$((copied + 1))
    copied_list+=("$rel")
  done < <(find "$src" -type f -print0)
}

# Common files first, then the pack overlay. Both share $force: without it,
# whichever copy is written first (common/) wins a collision; with it, the
# pack (written second) wins. See INSTALL.md "What gets installed".
copy_tree "$common_root"
copy_tree "$pack_version_dir"

# Special-case: install CLAUDE.md.template from the chosen pack to <target>/CLAUDE.md.
claude_dest="$target/CLAUDE.md"
if [ -e "$claude_dest" ] && [ "$force" -eq 0 ]; then
  skipped=$((skipped + 1))
  skipped_list+=("CLAUDE.md")
else
  cp "$pack_version_dir/$claude_template_rel" "$claude_dest"
  copied=$((copied + 1))
  copied_list+=("CLAUDE.md")
fi

# Continuity layer (continuity/ in this repo, rules in
# common/.claude/conventions/continuity-protocol.md). Never clobbers:
# files/ copies skip existing files (--force overwrites scaffold-owned ones,
# never docs/ or .gates/), merge/ appends only what is missing, and
# docs/STATE.md is rendered only when absent.
sed_escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

# merge_lines <src> <dest> <exact|firstword>: append src lines whose key is
# missing from dest, carrying the comment lines directly above each one.
merge_lines() {
  local src="$1" dest="$2" mode="$3" rel="${2#"$target"/}" pending="" added=0 line key
  if [ ! -e "$dest" ]; then
    cp "$src" "$dest"; copied=$((copied + 1)); copied_list+=("$rel"); return
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '') continue ;;
      '#'*) pending="$pending$line"$'\n'; continue ;;
    esac
    if [ "$mode" = firstword ]; then
      key="${line%% *}"; grep -qE "^$key( |$)" "$dest" && { pending=""; continue; }
    else
      grep -qxF -- "$line" "$dest" && { pending=""; continue; }
    fi
    if [ "$added" -eq 0 ]; then
      [ -n "$(tail -c 1 "$dest")" ] && echo >> "$dest"
      echo "# skaff continuity" >> "$dest"
    fi
    printf '%s%s\n' "$pending" "$line" >> "$dest"; pending=""; added=$((added + 1))
  done < "$src"
  if [ "$added" -gt 0 ]; then
    copied=$((copied + 1)); copied_list+=("$rel (merged $added line(s))")
  fi
}

install_continuity() {
  local cdir="$source_root/continuity" file rel dest protected index_new=0
  [ -d "$cdir" ] || return 0

  if [ -z "$human" ]; then
    local email
    email="$(git -C "$target" config user.email 2>/dev/null || git config user.email 2>/dev/null || true)"
    [ -n "$email" ] && human="human:${email%%@*}"
  fi

  while IFS= read -r -d '' file; do
    rel="${file#"$cdir/files"/}"
    dest="$target/$rel"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ]; then
      case "$rel" in docs/*|.gates/*) protected=1 ;; *) protected=0 ;; esac
      if [ "$force" -eq 0 ] || [ "$protected" -eq 1 ]; then
        skipped=$((skipped + 1)); skipped_list+=("$rel"); continue
      fi
    fi
    [ "$rel" = "docs/decisions/index.md" ] && index_new=1
    cp "$file" "$dest"
    case "$rel" in
      scripts/lib.sh)
        if [ -n "$human" ]; then
          sed -i.bak "s|@@CONTINUITY_HUMAN@@|$(sed_escape "$human")|" "$dest" && rm -f "$dest.bak"
        fi ;;
      scripts/*.sh|.githooks/*|.claude/hooks/*.sh) chmod +x "$dest" ;;
    esac
    copied=$((copied + 1)); copied_list+=("$rel")
  done < <(find "$cdir/files" -type f -print0)

  # Existing ADRs: regenerate the freshly copied index so pre-commit does not see it stale.
  if [ "$index_new" -eq 1 ] && ls "$target"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md >/dev/null 2>&1; then
    CLAUDE_PROJECT_DIR="$target" sh "$target/scripts/adr-index.sh" \
      || echo "Warning: could not regenerate docs/decisions/index.md; run scripts/adr-index.sh" >&2
  fi

  merge_lines "$cdir/merge/gitignore" "$target/.gitignore" exact
  merge_lines "$cdir/merge/gitattributes" "$target/.gitattributes" exact
  merge_lines "$cdir/merge/tool-versions" "$target/.tool-versions" firstword

  # .claude/settings.json: add each hook group whose command is not already configured.
  local settings="$target/.claude/settings.json"
  if [ ! -e "$settings" ]; then
    cp "$cdir/merge/settings.json" "$settings"; copied=$((copied + 1)); copied_list+=(".claude/settings.json")
  elif command -v jq >/dev/null 2>&1; then
    local merged
    merged="$(jq -s '
      .[0] as $d | .[1] as $s
      | $d + {hooks: (reduce ($s.hooks | to_entries[]) as $e (($d.hooks // {});
          (.[$e.key] // []) as $have
          | ([$have[].hooks[]?.command]) as $cmds
          | .[$e.key] = $have + [$e.value[] | select(([.hooks[].command] - $cmds) | length > 0)]))}
    ' "$settings" "$cdir/merge/settings.json" | tr -d '\r')"
    if [ "$merged" != "$(jq . "$settings" | tr -d '\r')" ]; then
      printf '%s\n' "$merged" > "$settings"; copied=$((copied + 1)); copied_list+=(".claude/settings.json (merged hooks)")
    fi
  else
    skipped=$((skipped + 1)); skipped_list+=(".claude/settings.json (jq missing: merge continuity/merge/settings.json hooks by hand)")
  fi

  # docs/STATE.md: rendered once, never overwritten.
  local state="$target/docs/STATE.md"
  if [ -e "$state" ]; then
    skipped=$((skipped + 1)); skipped_list+=("docs/STATE.md")
  else
    local repo today stale now
    repo="$(basename "$target")"
    today="$(date -u +%Y-%m-%d)"
    stale="$(date -u -d '+14 days' +%Y-%m-%d 2>/dev/null || date -u -v+14d +%Y-%m-%d)"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -n "$purpose" ] || purpose="Replace with one sentence on what $repo is for."
    purpose="$(printf '%s' "$purpose" | tr -d '"')"
    mkdir -p "$target/docs"
    sed -e "s|@@REPO@@|$(sed_escape "$repo")|g" \
        -e "s|@@DATE@@|$today|g" -e "s|@@STALE_AFTER@@|$stale|g" -e "s|@@GENERATED_AT@@|$now|g" \
        -e "s|@@PACK@@|$pack_name@$pack_version|g" \
        -e "s|@@PURPOSE@@|$(sed_escape "$purpose")|g" \
        -e "s|@@HUMAN@@|$(sed_escape "${human:-human:unknown}")|g" \
        "$cdir/templates/STATE.md.template" > "$state"
    copied=$((copied + 1)); copied_list+=("docs/STATE.md")
  fi

  if [ -z "$human" ]; then
    echo "Warning: no --human and no git user.email; set HUMAN in scripts/lib.sh before human gates" >&2
  fi
}

if [ "$continuity" -eq 1 ]; then
  install_continuity
fi

# Write pack identity sentinel (always, overwriting) so future tooling can
# detect the pack+version the target was bootstrapped from.
pack_sentinel="$target/.claude/.pack"
mkdir -p "$(dirname "$pack_sentinel")"
scaffold_commit="$(git -C "$source_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
cat > "$pack_sentinel" <<EOF
pack: $pack_name
version: $pack_version
installed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
scaffold_commit: $scaffold_commit
EOF

echo "Copied $copied file(s):"
for f in "${copied_list[@]}"; do
  echo "  + $f"
done

if [ "$skipped" -gt 0 ]; then
  echo
  echo "Skipped $skipped existing file(s) - re-run with --force to overwrite:"
  for f in "${skipped_list[@]}"; do
    echo "  - $f"
  done
fi

echo
echo "Pack identity written to .claude/.pack"
echo
echo "Done. Next steps:"
echo "  1. cd $target"
echo "  2. Review CLAUDE.md and .claude/conventions/"
echo "  3. git add . && git commit -m 'chore: bootstrap claude agent scaffold'"
if [ "$continuity" -eq 1 ]; then
  echo "  4. sh scripts/bootstrap.sh   (core.hooksPath, tool pins in .tool-versions, vale sync)"
  echo "  5. git switch -c chore/continuity && sh scripts/gate.sh A1   (runs scripts/selftest.sh)"
  echo "  6. set A1 status: done in docs/STATE.md, commit with trailer 'Closes-Item: A1'"
fi
