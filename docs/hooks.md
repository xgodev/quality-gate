# Enforcement hook (pre-push quality gate)

The plugin ships an **opt-in** `PreToolUse` hook that blocks `git push` and
`gh pr create` unless the quality gate passes for the current HEAD.

## What it does

On any `Bash` tool call, `hooks/pre-push-gate.sh` runs. It fast-exits for
everything except `git push` / `gh pr create`. For a gated command it:

1. Exempts non-code pushes: `--delete` / `-d`, `--tags`, `git push origin :branch`,
   and explicit `refs/tags/...` refspecs.
2. Resolves the base ref: the branch upstream (`@{upstream}`), else the remote
   default branch (`origin/HEAD`), else **absolute mode** (no base).
3. Runs `${CLAUDE_PLUGIN_ROOT}/qg [--base <ref>]` in the project.
4. Maps the gate exit code to a decision:
   - `0` passed / bypassed, `3` no supported language -> **allow**
   - `1` regressed / threshold, `2` tool error -> **deny** (JSON
     `permissionDecision: "deny"` with a concise reason)

## Bypass

The hook adds no bypass logic of its own. Exporting `QG_BYPASS_REASON` (already
honored by every gate, and audit-logged) makes the gate return `0`, so the push
is allowed. Example:

    QG_BYPASS_REASON="hotfix: gate infra down, reviewed manually" git push

## Fail-open by design

A broken hook must never brick git. If `jq` is missing, stdin is malformed,
`qg` is not found at `${CLAUDE_PLUGIN_ROOT}`, or the project is not a git repo,
the hook allows the command and prints a note to stderr.

## Registration

Declared in `hooks/hooks.json` (matcher `Bash`) and wired via the top-level
`"hooks": "./hooks/hooks.json"` path in `.claude-plugin/plugin.json`. The
script locates the gate through `${CLAUDE_PLUGIN_ROOT}` and the project
through `${CLAUDE_PROJECT_DIR}`.
