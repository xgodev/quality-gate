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

# Returns 0 (true) if a `git push ...` segment pushes NO code and is therefore
# exempt: a pure deletion (--delete/-d, or every refspec is a ':ref' delete or
# a 'refs/tags/*' tag) or a tag-only push (--tags with no refspec beyond the
# remote). Returns 1 (false) otherwise. Fail-safe: anything ambiguous -> false.
push_is_exempt() {
  local seg="$1"
  local rest="${seg#git push}"
  local has_tags=0 has_delete=0 npos=0 all_noncode=1 seen_remote=0 t
  for t in $rest; do
    case "$t" in
      --tags)        has_tags=1 ;;
      --delete|-d)   has_delete=1 ;;
      -*)            : ;;                 # ignore other flags
      *)
        npos=$((npos + 1))
        if [ "$seen_remote" -eq 0 ]; then
          seen_remote=1                   # first positional is the remote
        else
          case "$t" in
            :*|refs/tags/*) ;;            # delete or tag ref -> non-code
            *) all_noncode=0 ;;           # a code refspec
          esac
        fi
        ;;
    esac
  done
  [ "$has_delete" -eq 1 ] && return 0                      # all refspecs deleted
  [ "$npos" -ge 2 ] && [ "$all_noncode" -eq 1 ] && return 0  # only delete/tag refs
  [ "$has_tags" -eq 1 ] && [ "$npos" -le 1 ] && return 0     # tag-only push
  return 1
}

# --- decide whether any gated, non-exempt operation is present ------------
# Match `git push` / `gh pr create` as the leading tokens of any &&/||/;/|
# segment (not a bare substring), after stripping leading env assignments
# (FOO=bar cmd). Any non-exempt gated segment forces the gate to run.
should_gate=0
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//')"
  case "$seg" in
    "git push"|"git push "*)         push_is_exempt "$seg" || should_gate=1 ;;
    "gh pr create"|"gh pr create "*) should_gate=1 ;;   # never exempt PR creation
  esac
done <<< "$(printf '%s' "$cmd" | sed -E 's/(\|\||&&|;|\|)/\n/g')"

[ "$should_gate" -eq 1 ] || exit 0

# --- locate project + plugin ----------------------------------------------
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
plugin="${CLAUDE_PLUGIN_ROOT:-}"
qg_bin="$plugin/qg"
if [ -z "$plugin" ] || [ ! -x "$qg_bin" ]; then
  echo "qg-hook: qg not found at CLAUDE_PLUGIN_ROOT; skipping enforcement" >&2
  exit 0
fi
git -C "$proj" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0   # not a repo -> allow

# --- resolve base ref (upstream -> origin default -> absolute) ------------
base="$(git -C "$proj" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [ -z "$base" ]; then
  base="$(git -C "$proj" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
fi

# --- run the gate ----------------------------------------------------------
if [ -n "$base" ]; then
  out="$(cd "$proj" && "$qg_bin" --base "$base" 2>&1)"; rc=$?
else
  out="$(cd "$proj" && "$qg_bin" 2>&1)"; rc=$?   # absolute mode
fi

# --- map exit code to decision --------------------------------------------
case "$rc" in
  0|3) exit 0 ;;   # passed / bypassed / no-language -> allow
esac

verdict="regressed/failed"
[ "$rc" -eq 2 ] && verdict="tool error"
tail_out="$(printf '%s' "$out" | tail -n 6 | tr '\n' ' ')"
reason="Quality gate ${verdict} (qg exit ${rc}). ${tail_out} -- run the gate and fix, or set QG_BYPASS_REASON to override."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
