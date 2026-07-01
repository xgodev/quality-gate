# Design — pre-push quality-gate enforcement hook

Date: 2026-07-01
Status: approved (design phase)

## Problem

The `quality-gate` plugin ships a skill and the `qg` dispatcher, but nothing
*mechanically* enforces the gate before code leaves the machine. The skill is
deliberately advisory ("green = signal, not action") and never runs
`gh pr create` / `git push` on its own. A developer (or the model) can push or
open a PR without ever running the gate. This design adds an opt-in
**PreToolUse hook**, bundled inside the plugin, that blocks `git push` and
`gh pr create` unless the gate passes for the current HEAD (or an explicit
bypass is declared).

## Decisions (locked with the user)

1. **Verification = re-run the gate.** The hook runs `qg` synchronously at
   push/PR-create time. Authoritative; impossible to bypass without an explicit
   `QG_BYPASS_REASON`. No new state/sentinel file in `qg`. Cost: the gate's
   latency is added to each gated push (accepted).
2. **Base ref = upstream tracking branch.** Compare against `@{upstream}` (what
   the push updates / what the PR compares). Fallbacks below.
3. **Escape hatch = explicit bypass + safe edge cases.** Honor
   `QG_BYPASS_REASON` (already audit-logged by the gate). Non-code operations do
   not block. Gate tool-error (exit 2) **blocks** (never mask infra failure as
   approved).

### Reconciliations approved during brainstorming

- **Do not depend on the hook `if` field.** Use `matcher: "Bash"` and parse
  `.tool_input.command` inside the script. Rationale: CLAUDE.md forbids guessing
  plugin specifics; script parsing is robust and unit-testable.
- **No upstream (new/WIP branch) → absolute mode**, not skip. The gate still
  runs and enforces absolute thresholds. WIP escape is the explicit
  `QG_BYPASS_REASON`, never a silent skip (aligns with CLAUDE.md "never mask").
- **Force-push is gated** (it changes PR content). Only `git push --delete` and
  tag-only / pure-delete pushes are exempt as non-code operations.

## Architecture

Single bundled bash script fired by a `PreToolUse` hook on the `Bash` matcher.

```
hooks/hooks.json            # declares the PreToolUse hook (matcher: "Bash")
hooks/pre-push-gate.sh      # reads stdin JSON, decides allow/deny
.claude-plugin/plugin.json  # gains a "hooks" key pointing at hooks/hooks.json
```

The hook fires on every `Bash` call, so step 1 must be a cheap fast-exit.

### Script control flow (`hooks/pre-push-gate.sh`)

1. Read stdin JSON; extract the command: `cmd=$(jq -r '.tool_input.command')`.
   Also read `CLAUDE_PROJECT_DIR` and `CLAUDE_PLUGIN_ROOT` from the environment
   (both exported to the hook subprocess).
2. **Fast-exit (allow):** if `cmd` matches neither `git push` nor
   `gh pr create`, `exit 0` with no output. This is the common case.
3. **Non-code operation (allow):** for `git push`, if the command is a branch
   deletion (`--delete` / `-d`, or a `:refspec` delete form) or pushes only
   tags (`--tags`, or an explicit `refs/tags/...` / tag-only refspec), `exit 0`.
4. **Resolve base ref:**
   - `BASE="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)"`.
   - Else the remote default branch: `origin/HEAD` →
     `git symbolic-ref refs/remotes/origin/HEAD` (strip to `origin/main` etc.).
   - Else: no base → **absolute mode** (call `qg` without `--base`).
5. **Run the gate:**
   `out=$(cd "$CLAUDE_PROJECT_DIR" && "$CLAUDE_PLUGIN_ROOT/qg" ${BASE:+--base "$BASE"} 2>&1)`;
   capture `rc=$?`.
6. **Map exit code → decision:**
   | `qg` exit | meaning | hook decision |
   |-----------|---------|---------------|
   | `0` | passed / bypassed / fast-path | **allow** |
   | `3` | no supported language | **allow** (nothing to gate) |
   | `1` | regressed / absolute threshold violated | **deny** |
   | `2` | setup/tool error | **deny** |

### Blocking mechanism

Emit JSON on stdout (the docs-recommended path, cleaner than `exit 2`):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Quality gate <verdict>: <concise tail of qg output>. Run the gate and fix, or set QG_BYPASS_REASON to override."
  }
}
```

Allow decisions are a bare `exit 0` with no stdout (defer to normal permission
flow). The deny reason includes a concise tail of the gate output so the model/
user sees *why* it was blocked.

### Bypass

Inherited for free. `QG_BYPASS_REASON` is already honored by the gate itself
(returns exit 0 = bypassed, audit-logged). Since the hook re-runs `qg`, an
operator who exports `QG_BYPASS_REASON` makes the gate return 0 and the hook
allows. **The hook needs no separate bypass code.**

> Implementation-verify: confirm the per-language gates read `QG_BYPASS_REASON`
> and short-circuit to exit 0. If any gate does not, either fix it there or add
> an explicit bypass check in the hook. This is a task in the plan, not an
> assumption baked into shipping code.

## Error handling / edge cases

- `jq` missing or malformed stdin → the hook must fail **open** (allow) with a
  stderr note, never hard-lock the user's git out of a `jq` bug. (A broken hook
  should not brick pushing; enforcement degrades gracefully.)
- Not inside a git repo / `CLAUDE_PROJECT_DIR` unset → allow (nothing to gate).
- `qg` itself missing/non-executable at `CLAUDE_PLUGIN_ROOT` → allow with a
  stderr note (misconfiguration must not brick git).
- Command contains `git push` as a substring of an unrelated command
  (e.g. `echo "git push"`) → parsing keys on the leading tokens of each
  `;`/`&&`/`|`-separated segment, not a bare substring, to avoid false blocks.

## Testing (bats, under `tests/`)

- Fast-exit: non-push Bash command → exit 0, no stdout.
- `git push` with failing gate (stub `qg` → exit 1) → deny JSON.
- `git push` with tool-error gate (stub `qg` → exit 2) → deny JSON.
- `git push` with passing gate (stub `qg` → exit 0) → allow (exit 0, no deny).
- `qg` exit 3 (no language) → allow.
- `git push --delete` / tag-only push → allow without running the gate.
- `gh pr create` with failing gate → deny.
- Malformed stdin / missing `jq` → fail open (allow).
- Base resolution: upstream present vs absent (absolute mode) exercises the
  `--base` argument shape.

Tests stub `qg` via `CLAUDE_PLUGIN_ROOT` pointing at a fixture dir so no real
language toolchain is needed.

## Repo discipline (CLAUDE.md hard rules — same commit)

- **Version bump across 3 files:** `.claude-plugin/plugin.json` `version`
  (0.2.5 → 0.3.0, new feature), the README version line, and a `CHANGELOG.md`
  entry.
- **Docs updated same change:** README (new "Enforcement hook" section
  explaining opt-in, what it blocks, bypass), a `docs/` page (e.g.
  `docs/hooks.md`) documenting the hook contract, and any CLAUDE.md note if the
  hook changes stated behavior.
- **English only, zero proprietary references, generic examples.**
- **Plugin manifest `description`** updated if it no longer matches reality
  (the plugin now also enforces, not only measures).

## Out of scope (YAGNI)

- No CI GitHub Action (that was a different enforcement option not chosen).
- No git-native `pre-push` hook install (Claude Code plugin hook only).
- No persisted pass-state / sentinel in `qg` (re-run approach chosen).
- No new base-ref inference from `gh pr create --base` parsing (upstream chosen
  as the single base strategy).
