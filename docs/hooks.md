# Enforcement hook (pre-push quality gate)

The plugin ships an **opt-in** `PreToolUse` hook that blocks `git push` and
`gh pr create` unless the quality gate passes for the current HEAD.

## What it does

On any `Bash` tool call, `hooks/pre-push-gate.sh` runs. It fast-exits for
everything except `git push` / `gh pr create`. For a gated command it:

1. Exempts non-code pushes only: a pure deletion (`--delete` / `-d`, or every
   refspec is a `:branch` delete or a `refs/tags/...` tag), or a tag-only push
   (`--tags` with no branch/commit refspec beyond the remote). Mixing a tag or
   delete with a real code refspec (e.g. `git push origin main --tags`) is still
   gated.
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

Declared in `hooks/hooks.json` (matcher `Bash`), which Claude Code loads
**automatically** because it sits at the plugin's standard hooks path. The
plugin manifest must NOT also reference it: a `"hooks": "./hooks/hooks.json"`
key in `.claude-plugin/plugin.json` duplicates the auto-loaded file and makes
the whole plugin fail to load (`manifest.hooks` is only for *additional*,
non-standard hook files). The script locates the gate through
`${CLAUDE_PLUGIN_ROOT}` and the project through `${CLAUDE_PROJECT_DIR}`.

## Known limitations

This hook is **advisory enforcement**, not a hard security boundary: it is
opt-in and it fails open. Detection keys on the leading tokens of each command
segment, so a few uncommon forms that push code are not gated -- notably
`git -C <dir> push ...`, a push wrapped in a subshell (`(git push ...)`), or
`eval`-ed push commands. The common forms (`git push origin main`,
`git push -u origin <branch>`, `A=b git push`, `... && git push`) are all
gated. If you need a hard gate that cannot be sidestepped, enforce `qg` in CI
as well -- the hook is a fast local check, not a replacement for a server-side
gate.
