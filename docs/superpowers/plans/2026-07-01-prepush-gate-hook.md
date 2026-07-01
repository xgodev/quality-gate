# Pre-push Quality-Gate Enforcement Hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a PreToolUse hook, bundled in the `quality-gate` plugin, that blocks `git push` / `gh pr create` unless the gate passes for HEAD (or `QG_BYPASS_REASON` is set).

**Architecture:** A single bundled bash script (`hooks/pre-push-gate.sh`) is fired by a `PreToolUse` hook on the `Bash` matcher (declared in `hooks/hooks.json`, wired via `.claude-plugin/plugin.json`). The script parses the tool command, fast-exits for anything that is not a gated push/PR-create, re-runs `qg` synchronously against the upstream base ref, and denies via `permissionDecision: "deny"` JSON when the gate returns exit 1 or 2. It fails **open** on its own errors so a broken hook never bricks git.

**Tech Stack:** Bash, `jq`, `git`, the existing `qg` dispatcher, `bats` (v1.5.0+) for tests.

Spec: `docs/superpowers/specs/2026-07-01-prepush-gate-hook-design.md`.
Branch: `feat/prepush-gate-hook`.

## Global Constraints

- **English only, everywhere** — code, comments, runtime strings, docs. No Portuguese.
- **Zero proprietary/internal references.** Generic examples only (`origin/main`, `my-project`).
- **ASCII identifiers/examples**; no accents, no em-dash (use `--`).
- **Fail OPEN on the hook's own errors** (missing `jq`, missing `qg`, malformed stdin, not a git repo). A broken hook must never block the user's git. Enforcement degrades with a `stderr` note.
- **Never mask infra as approval:** `qg` exit `2` (tool error) → **deny**, never allow.
- **Exit-code contract of `qg`:** `0` pass/bypassed/fast-path → allow; `1` regressed/threshold → deny; `2` setup/tool error → deny; `3` no supported language → allow.
- **Bypass is inherited:** all 9 gates already honor `QG_BYPASS_REASON` (verified at `nodejs/qg.sh:197`); the hook adds **no** bypass code — an operator exporting it makes `qg` return 0 and the hook allows.
- **Blocking mechanism:** JSON on stdout — `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` — never `exit 2`.
- **Version discipline (same commit):** bump `.claude-plugin/plugin.json` `version` 0.2.5 → 0.3.0, add a `CHANGELOG.md` `[0.3.0]` entry, and update `README.md` docs. (README has no literal version line; the README update is the new hook section + Documentation-list entry.)
- **Bats convention:** `load 'helpers/setup'`, `qg_clean_env` in `setup()`, temp dirs via `mktemp`, scripts referenced via helpers.

---

### Task 1: Hook skeleton + wiring + fast-exit

Produces a registered PreToolUse hook that reads stdin and allows everything (no gating yet). This isolates the plugin-registration risk into one reviewable task.

**Files:**
- Create: `hooks/pre-push-gate.sh`
- Create: `hooks/hooks.json`
- Modify: `.claude-plugin/plugin.json` (add `hooks` key)
- Modify: `tests/helpers/setup.bash` (add hook helpers)
- Test: `tests/hook-prepush.bats`

**Interfaces:**
- Produces: `hooks/pre-push-gate.sh` — reads hook JSON on stdin, writes a `permissionDecision: "deny"` JSON to stdout to block, or `exit 0` with no stdout to allow.
- Produces helpers (`tests/helpers/setup.bash`):
  - `qg_hook_path()` → echoes `$QG_REPO_ROOT/hooks/pre-push-gate.sh`
  - `qg_make_stub_plugin RC` → makes a temp dir containing an executable `qg` stub that echoes its args and `exit RC`; echoes the dir path
  - `qg_make_git_repo` → makes a temp dir, `git init -q`, one empty commit; echoes the dir path

- [ ] **Step 1: Write the failing test**

Create `tests/hook-prepush.bats`:

```bash
#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "hook: non-push Bash command is allowed with no output (fast-exit)" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"ls -la\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hooks.json declares a PreToolUse Bash matcher" {
  run jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$QG_REPO_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

@test "plugin.json references the hooks file" {
  run jq -e '.hooks' "$QG_REPO_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Add test helpers to `tests/helpers/setup.bash`**

Append:

```bash
# --- pre-push hook helpers -------------------------------------------------
qg_hook_path() {
  echo "$QG_REPO_ROOT/hooks/pre-push-gate.sh"
}

# Makes a temp "plugin root" holding a qg stub that exits with RC and echoes
# its args to stderr (so tests can assert --base forwarding).
qg_make_stub_plugin() {
  local rc="$1"
  local d
  d="$(mktemp -d -t qg-plugin-XXXXXX)"
  cat > "$d/qg" <<EOF
#!/usr/bin/env bash
echo "stub-qg-args: \$*" >&2
exit $rc
EOF
  chmod +x "$d/qg"
  echo "$d"
}

# Makes a temp git repo with one commit; echoes its path.
qg_make_git_repo() {
  local d
  d="$(mktemp -d -t qg-repo-XXXXXX)"
  git -C "$d" init -q
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$d"
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bats tests/hook-prepush.bats`
Expected: FAIL — `pre-push-gate.sh` / `hooks.json` do not exist yet.

- [ ] **Step 4: Create `hooks/pre-push-gate.sh` (skeleton: read stdin, allow all)**

```bash
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
```

Make it executable: `chmod +x hooks/pre-push-gate.sh`.

- [ ] **Step 5: Create `hooks/hooks.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/pre-push-gate.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Wire `hooks` into `.claude-plugin/plugin.json`**

Add a top-level `"hooks": "./hooks/hooks.json"` key (after `"version"`). Final shape:

```json
{
  "name": "quality-gate",
  "version": "0.3.0",
  "hooks": "./hooks/hooks.json",
  "description": "...",
  "author": { "name": "xgodev" },
  "repository": "https://github.com/xgodev/quality-gate.git"
}
```

> Note: the version bump to `0.3.0` lands here (single edit); CHANGELOG/README follow in Task 5. `plugin.json` is committed together with them only if you prefer — but bumping here keeps the manifest honest the moment the hook exists.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bats tests/hook-prepush.bats`
Expected: PASS (3 tests).

- [ ] **Step 8: Manual registration smoke-test (plugin-specifics verification)**

CLAUDE.md forbids guessing plugin specifics. Confirm the hook actually registers before trusting it:

Run: `claude --debug` in a throwaway project with the plugin loaded, issue a `git push` (dry), and confirm the hook fires (debug log shows the PreToolUse command). If the `"hooks": "./hooks/hooks.json"` path form does NOT register, fall back to the inline object form in `plugin.json` (copy the `hooks` object from `hooks/hooks.json` inline) OR rely on auto-discovery of `hooks/hooks.json` and remove the `plugin.json` key. Document whichever form works in `docs/hooks.md` (Task 5).

- [ ] **Step 9: Commit**

```bash
git add hooks/ .claude-plugin/plugin.json tests/hook-prepush.bats tests/helpers/setup.bash
git commit -m "feat(hook): PreToolUse skeleton + registration (fast-exit allow)"
```

---

### Task 2: Detect gated operations + exempt non-code pushes

**Files:**
- Modify: `hooks/pre-push-gate.sh`
- Test: `tests/hook-prepush.bats`

**Interfaces:**
- Consumes: the skeleton's `$cmd` variable.
- Produces: a `push_is_exempt()` helper and a `should_gate` decision. The script `exit 0` (allow) when no gated, non-exempt operation is present; otherwise it falls through to Task 3's gate-execution block. Exemption is decided per segment and per push (fail-safe: any non-exempt gated segment gates the whole command).

- [ ] **Step 1: Write the failing tests**

Append to `tests/hook-prepush.bats`:

```bash
@test "hook: 'echo git push' is NOT gated (substring, not a command)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # stub would deny if reached
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"echo git push\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push --delete origin foo' is exempt (branch deletion)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push --delete origin foo\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push origin :foo' is exempt (refspec delete)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin :foo\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push --tags' is exempt (tag-only push)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push --tags\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/hook-prepush.bats -f "exempt|substring"`
Expected: the delete/refspec/tags tests FAIL (script does not yet gate, so it allows — but so does the current skeleton, so they may PASS trivially). To make them meaningful they must fail once gating exists; verify by temporarily asserting the deny path. Practically: proceed to Step 3, then confirm these stay green while Task 3's deny tests go red-then-green.

> Note: these four tests assert the *allow* path; they guard against future over-blocking. They pass on the skeleton and must KEEP passing after Task 3. Treat them as regression guards, not red-first tests.

- [ ] **Step 3: Add gating detection + exemptions to `hooks/pre-push-gate.sh`**

Replace the `# (gating logic added in later tasks)` line with the block
below. It decides **per segment** whether any gated, non-exempt operation is
present. A push is exempt only when it pushes **no code** — a pure deletion or
a tag-only push. Exemption is fail-safe: on any ambiguity (mixed code+tag,
mixed code+delete, unknown form) it gates. `gh pr create` is never exempt.
Written without bash arrays so it runs under bash 3.2 (macOS system bash).

```bash
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
```

The four bats tests from Step 1 remain valid regression guards (pure delete,
`:refspec` delete, `--tags`, and the `echo git push` substring case all still
resolve to allow). The **discriminating** cases that separate exempt from
non-exempt (`git push origin main --tags`, `git push && git push --tags`) can
only be asserted once the deny path exists, so they are added in Task 3.

- [ ] **Step 4: Run to verify exemption tests pass**

Run: `bats tests/hook-prepush.bats`
Expected: PASS (all existing tests still green).

- [ ] **Step 5: Commit**

```bash
git add hooks/pre-push-gate.sh tests/hook-prepush.bats
git commit -m "feat(hook): detect gated push/pr-create ops, exempt tag/delete pushes"
```

---

### Task 3: Resolve base ref, run the gate, map exit code to decision

**Files:**
- Modify: `hooks/pre-push-gate.sh`
- Test: `tests/hook-prepush.bats`

**Interfaces:**
- Consumes: control reaching this point (Task 2 already `exit 0`ed unless `should_gate=1`), plus `$cmd`, env `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`.
- Produces: the terminal behavior — allow (`exit 0`, no stdout) for `qg` exit 0/3; deny JSON for `qg` exit 1/2.

- [ ] **Step 1: Write the failing tests**

Append to `tests/hook-prepush.bats`:

```bash
@test "hook: gate exit 1 (regressed) -> deny JSON" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 2 (tool error) -> deny JSON (never masked)" {
  local plug proj
  plug="$(qg_make_stub_plugin 2)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"gh pr create\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 0 (passed) -> allow, no stdout" {
  local plug proj
  plug="$(qg_make_stub_plugin 0)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 3 (no language) -> allow, no stdout" {
  local plug proj
  plug="$(qg_make_stub_plugin 3)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: absolute mode when no upstream (qg called WITHOUT --base)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # deny path so the stub args surface in the reason
  proj="$(qg_make_git_repo)"        # fresh repo: no upstream, no origin/HEAD
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("stub-qg-args:")'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("--base") | not'
  rm -rf "$plug" "$proj"
}

@test "hook: base resolved from origin/HEAD is forwarded as --base" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # deny path so the stub args surface
  proj="$(qg_make_git_repo)"
  # fabricate a remote default branch: origin/main -> HEAD, origin/HEAD -> origin/main
  git -C "$proj" update-ref refs/remotes/origin/main "$(git -C "$proj" rev-parse HEAD)"
  git -C "$proj" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("--base origin/main")'
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push origin main --tags' is GATED (code + tags, not exempt)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # stub denies if the gate runs
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin main --tags\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push && git push --tags' is GATED (first push is non-exempt)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push && git push --tags\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: pure 'git push --tags' stays exempt even with a failing gate stub" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # would deny IF the gate ran
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push --tags\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]   # exempt -> allowed without running the gate
  rm -rf "$plug" "$proj"
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/hook-prepush.bats -f "gate exit|absolute|GATED"`
Expected: FAIL — the script currently `exit 0`s after the gating decision without running `qg`.

- [ ] **Step 3: Append gate execution + decision mapping to `hooks/pre-push-gate.sh`**

After the exemption block, add:

```bash
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
```

- [ ] **Step 4: Run the full suite**

Run: `bats tests/hook-prepush.bats`
Expected: PASS (all tests, including the Task 2 regression guards).

- [ ] **Step 5: Commit**

```bash
git add hooks/pre-push-gate.sh tests/hook-prepush.bats
git commit -m "feat(hook): run qg vs upstream base, deny on exit 1/2, allow on 0/3"
```

---

### Task 4: Fail-open robustness

**Files:**
- Modify: `tests/hook-prepush.bats` (the script already fails open; this task proves it and closes gaps).

**Interfaces:**
- Consumes: the complete script from Task 3.
- Produces: verified fail-open behavior for missing `qg`, malformed stdin, non-repo project.

- [ ] **Step 1: Write the failing/guard tests**

Append:

```bash
@test "hook: missing qg at plugin root -> allow (fail open)" {
  local plug proj
  plug="$(mktemp -d -t qg-noplug-XXXXXX)"   # empty: no qg binary
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]   # no deny JSON on stdout
  rm -rf "$plug" "$proj"
}

@test "hook: malformed stdin -> allow (fail open)" {
  run bash -c 'printf "%s" "not json at all" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: gated push but project is not a git repo -> allow" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(mktemp -d -t qg-norepo-XXXXXX)"   # not a git repo
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git push origin HEAD\"}}" | "$(qg_hook_path)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}
```

- [ ] **Step 2: Run the tests**

Run: `bats tests/hook-prepush.bats -f "fail open|not a git repo"`
Expected: PASS — the Task 3 script already guards all three (missing `qg`, `jq -r ... // empty` on bad JSON, `rev-parse` guard). If any fails, fix the corresponding guard in `hooks/pre-push-gate.sh` (do not weaken enforcement for the valid path).

- [ ] **Step 3: Run the entire repo test suite (no regressions elsewhere)**

Run: `bats tests/`
Expected: PASS (existing language/dispatcher suites unaffected).

- [ ] **Step 4: Commit**

```bash
git add tests/hook-prepush.bats
git commit -m "test(hook): prove fail-open on missing qg / bad stdin / non-repo"
```

---

### Task 5: Docs + version bump (CLAUDE.md discipline)

**Files:**
- Create: `docs/hooks.md`
- Modify: `README.md` (new "Enforcement hook" section + Documentation-list entry)
- Modify: `CHANGELOG.md` (new `[0.3.0]` entry)
- Modify: `.claude-plugin/plugin.json` (`description` — plugin now enforces, not only measures; `version` already 0.3.0 from Task 1)

**Interfaces:** none (documentation).

- [ ] **Step 1: Create `docs/hooks.md`**

```markdown
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

Declared in `hooks/hooks.json` (matcher `Bash`) and wired via
`.claude-plugin/plugin.json`. The script locates the gate through
`${CLAUDE_PLUGIN_ROOT}` and the project through `${CLAUDE_PROJECT_DIR}`.
```

> If Task 1 Step 8 found a different registration form works, document THAT form here.

- [ ] **Step 2: Add a README section + Documentation-list entry**

In `README.md`, add after the "How it works" section a short "Enforcement hook" subsection (2-4 sentences: opt-in, blocks `git push`/`gh pr create` unless the gate passes, `QG_BYPASS_REASON` overrides, fail-open). Add to the Documentation list:

```markdown
- [`docs/hooks.md`](docs/hooks.md) -- the opt-in pre-push enforcement hook (blocks push/PR-create on a failing gate).
```

- [ ] **Step 3: Add the `[0.3.0]` CHANGELOG entry**

Insert at the top of `CHANGELOG.md` (above `## [0.2.5]`):

```markdown
## [0.3.0]

Feature: opt-in pre-push enforcement hook. A bundled `PreToolUse` hook
(`hooks/pre-push-gate.sh`, declared in `hooks/hooks.json`) blocks `git push`
and `gh pr create` unless the gate passes for HEAD. It re-runs `qg` against the
branch upstream (`@{upstream}` -> `origin/HEAD` -> absolute mode), denies on
`qg` exit 1 (regressed/threshold) or 2 (tool error), and allows on 0
(passed/bypassed) or 3 (no supported language). Non-code pushes
(`--delete`/`-d`, `--tags`, `:refspec` delete, `refs/tags/...`) are exempt.
Bypass is inherited: exporting `QG_BYPASS_REASON` makes the gate pass. The hook
fails OPEN on its own errors (missing `jq`/`qg`, malformed stdin, non-repo) so a
broken hook never bricks git. Adds `tests/hook-prepush.bats`. Docs: `docs/hooks.md`.
```

- [ ] **Step 4: Update `plugin.json` `description`**

Append to the existing description a clause reflecting enforcement, e.g. `... absolute (no-base) mode; ships an opt-in pre-push hook that blocks push/PR-create on a failing gate.` Keep it one line, English, ASCII.

- [ ] **Step 5: Verify no Portuguese / proprietary strings crept in**

Run:
```bash
grep -rniE 'carrefour|bitbucket' . --include='*.sh' --include='*.json' --include='*.md' | grep -v '\.git/'
```
Expected: empty. Eyeball the new files for any non-English string.

- [ ] **Step 6: Run the full suite once more**

Run: `bats tests/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add docs/hooks.md README.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: document pre-push hook; bump 0.2.5 -> 0.3.0 (CHANGELOG + manifest)"
```

---

## Self-Review

**Spec coverage:**
- Re-run verification → Task 3 (runs `qg`). ✔
- Upstream base + fallbacks → Task 3 base-resolution block. ✔
- Escape hatch / `QG_BYPASS_REASON` inheritance → Global Constraints + Task 5 docs; no code needed (verified all gates honor it). ✔
- `if`-field avoidance (matcher `Bash` + script parse) → Task 1/2. ✔
- No-upstream → absolute mode → Task 3 test "absolute mode when no upstream". ✔
- Force-push gated; only delete/tag exempt → Task 2 exemptions (no force exemption present). ✔
- Blocking via `permissionDecision: deny` JSON → Task 3. ✔
- Fail-open edge cases → Task 4. ✔
- Substring false-block avoidance → Task 2 "echo git push" test. ✔
- Bats tests, version bump 3 places, docs → Tasks 1-5. ✔

**Placeholder scan:** No TBD/TODO in steps; every code step shows full code. The only conditional ("if the path form does not register, fall back...") is a genuine verification branch, with both concrete forms named.

**Type/name consistency:** helper names (`qg_hook_path`, `qg_make_stub_plugin`, `qg_make_git_repo`), the `push_is_exempt()` helper, and variables (`should_gate`, `base`, `qg_bin`, `out`, `rc`) are used consistently across Tasks 1-4. JSON shape identical in Task 3 code and Task 5 docs.

**Known risk:** plugin hook registration form (`plugin.json` path key vs inline vs auto-discovered `hooks/hooks.json`) is verified manually in Task 1 Step 8, not assumed — per CLAUDE.md "do not guess plugin specifics."
