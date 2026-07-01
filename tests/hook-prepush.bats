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
