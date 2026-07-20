#!/usr/bin/env bats
# The QG hook gates ONLY `gh pr create`. `git push` is NEVER gated: the gate
# belongs to the PR moment (and CI), not to every push.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "hook: non-pr Bash command is allowed with no output (fast-exit)" {
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"ls -la\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: 'git push' is NEVER gated -- even with a failing gate stub" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin main\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git add && git push' compound is NEVER gated" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git add -A && git push\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'echo gh pr create' is NOT gated (substring, not a command)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"echo gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 1 (regressed) on gh pr create -> deny JSON" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create --fill\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 2 (tool error) on gh pr create -> deny JSON (never masked)" {
  local plug proj
  plug="$(qg_make_stub_plugin 2)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 0 (passed) on gh pr create -> allow, no stdout" {
  local plug proj
  plug="$(qg_make_stub_plugin 0)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 3 (no language) on gh pr create -> allow, no stdout" {
  local plug proj
  plug="$(qg_make_stub_plugin 3)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: absolute mode when no upstream (qg called WITHOUT --base)" {
  # Failing stub: the deny reason embeds the stub's argv, so the assertion
  # sees what the hook actually forwarded. (A passing stub produces NO
  # output at all -- nothing to assert on.)
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run --separate-stderr bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\" 2>&1"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'stub-qg-args:'
  if printf '%s' "$output" | grep -q -- '--base'; then
    echo "hook forwarded --base with no upstream: $output"; return 1
  fi
  rm -rf "$plug" "$proj"
}

@test "hook: base resolved from origin/HEAD is forwarded as --base" {
  # Failing stub for the same reason as above: only the deny path surfaces
  # the forwarded argv.
  local plug proj clone
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  clone="$(mktemp -d -t qg-clone-XXXXXX)"
  git clone -q "$proj" "$clone/repo"
  git -C "$clone/repo" remote set-head origin -a >/dev/null 2>&1 || true
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$clone/repo" \
    run --separate-stderr bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\" 2>&1"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q -- '--base origin/'
  rm -rf "$plug" "$proj" "$clone"
}

@test "hook: missing qg at plugin root -> allow (fail open)" {
  local plug proj
  plug="$(mktemp -d -t qg-noplugin-XXXXXX)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run --separate-stderr bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]   # stdout empty (no deny); the skip note goes to stderr
  rm -rf "$plug" "$proj"
}

@test "hook: malformed stdin -> allow (fail open)" {
  run bash -c "printf '%s' 'not-json' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
}

@test "hook: gated pr create but project is not a git repo -> allow" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(mktemp -d -t qg-norepo-XXXXXX)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}
