#!/usr/bin/env bash
# pre-push-gate.sh -- PreToolUse hook (quality-gate plugin).
# Blocks `git push` / `gh pr create` unless the gate passes for HEAD.
# English only. Fails OPEN on its own errors: a broken hook must never
# brick the user's git.

set -uo pipefail

input="$(cat)"

# jq is required to parse the tool input; without it, fail open.
if ! command -v jq >/dev/null 2>&1; then
  echo "qg-hook: jq not found; skipping gate enforcement" >&2
  exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0   # not a readable Bash command -> allow

# --- is this a gated operation? -------------------------------------------
# Match `git push` / `gh pr create` as the leading tokens of any
# &&/||/;/| segment (not a bare substring), after stripping leading env
# assignments (FOO=bar cmd).
is_gated=0
gated_kind=""
gated_seg=""
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//')"
  case "$seg" in
    "git push"|"git push "*)       is_gated=1; gated_kind="push"; gated_seg="$seg" ;;
    "gh pr create"|"gh pr create "*) is_gated=1; gated_kind="pr";  gated_seg="$seg" ;;
  esac
done <<< "$(printf '%s' "$cmd" | sed -E 's/(\|\||&&|;|\|)/\n/g')"

[ "$is_gated" -eq 1 ] || exit 0

# --- non-code push operations are exempt ----------------------------------
if [ "$gated_kind" = "push" ]; then
  case " $gated_seg " in
    *" --delete "*|*" -d "*) exit 0 ;;   # branch deletion
    *" --tags "*)            exit 0 ;;   # tag-only push
  esac
  case "$gated_seg" in
    *" :"*)          exit 0 ;;           # refspec delete: git push origin :foo
    *"refs/tags/"*)  exit 0 ;;           # explicit tag refspec
  esac
fi
