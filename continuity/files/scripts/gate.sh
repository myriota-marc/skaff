#!/bin/sh
# Run a next_actions item's "test:" done_when; on pass write .gates/<ID>.json.
set -eu
. "$(dirname "$0")/lib.sh"
id="${1:?usage: scripts/gate.sh <ID>}"
line="$(state_items | grep -E "\{id: $id," || true)"
[ -n "$line" ] || { echo "gate: no next_actions item $id in docs/STATE.md" >&2; exit 1; }
dw="$(item_field "$line" done_when)"
case "$dw" in "test: "*) cmd="${dw#test: }" ;; *) echo "gate: $id is not a test gate ($dw)" >&2; exit 1 ;; esac
cd "$ROOT"
sh -c "$cmd" || { echo "gate: $id FAILED: $cmd" >&2; exit 1; }
mkdir -p .gates
jq -n --arg id "$id" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg head "$(git rev-parse HEAD)" --arg cmd "$cmd" \
  '{id:$id, by:"process:gate", at:$at, head:$head, cmd:$cmd, exit:0}' > ".gates/$id.json"
echo "gate: $id passed, evidence .gates/$id.json"
