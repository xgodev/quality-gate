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

# (gating logic added in later tasks)
exit 0
