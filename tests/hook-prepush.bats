#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "hook: non-push Bash command is allowed with no output (fast-exit)" {
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"ls -la\"}}' | \"$(qg_hook_path)\""
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

@test "hook: 'echo git push' is NOT gated (substring, not a command)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # stub would deny if reached
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"echo git push\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push --delete origin foo' is exempt (branch deletion)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push --delete origin foo\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push origin :foo' is exempt (refspec delete)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin :foo\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push --tags' is exempt (tag-only push)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push --tags\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}
