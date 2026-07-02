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

@test "plugin.json does NOT declare a hooks key (standard hooks/hooks.json auto-loads; a manifest ref duplicates it)" {
  run jq -e '.hooks' "$QG_REPO_ROOT/.claude-plugin/plugin.json"
  [ "$status" -ne 0 ]
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

@test "hook: gate exit 1 (regressed) -> deny JSON" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 2 (tool error) -> deny JSON (never masked)" {
  local plug proj
  plug="$(qg_make_stub_plugin 2)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 0 (passed) -> allow, no stdout" {
  local plug proj
  plug="$(qg_make_stub_plugin 0)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: gate exit 3 (no language) -> allow, no stdout" {
  local plug proj
  plug="$(qg_make_stub_plugin 3)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}

@test "hook: absolute mode when no upstream (qg called WITHOUT --base)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # deny path so the stub args surface in the reason
  proj="$(qg_make_git_repo)"        # fresh repo: no upstream, no origin/HEAD
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\""
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
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\""
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
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin main --tags\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: 'git push && git push --tags' is GATED (first push is non-exempt)" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push && git push --tags\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$plug" "$proj"
}

@test "hook: pure 'git push --tags' stays exempt even with a failing gate stub" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"   # would deny IF the gate ran
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push --tags\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]   # exempt -> allowed without running the gate
  rm -rf "$plug" "$proj"
}

@test "hook: missing qg at plugin root -> allow (fail open)" {
  local plug proj
  plug="$(mktemp -d -t qg-noplug-XXXXXX)"   # empty: no qg binary
  proj="$(qg_make_git_repo)"
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\" 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]   # no deny JSON on stdout
  rm -rf "$plug" "$proj"
}

@test "hook: malformed stdin -> allow (fail open)" {
  run bash -c "printf '%s' 'not json at all' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: gated push but project is not a git repo -> allow" {
  local plug proj
  plug="$(qg_make_stub_plugin 1)"
  proj="$(mktemp -d -t qg-norepo-XXXXXX)"   # not a git repo
  CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$proj" \
    run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push origin HEAD\"}}' | \"$(qg_hook_path)\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$plug" "$proj"
}
