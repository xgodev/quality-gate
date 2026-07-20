#!/usr/bin/env bash
# Shared across every language gate: resolve the set of files a PR touches.
#
# This was copied byte-for-byte into each <lang>/qg.sh. It is factored out here
# because the Rust gate now derives its measurement SCOPE from this set (issue
# 17), and a scoping bug that only exists in one of eight copies is a bug nobody
# finds. Everything else about the fast-path -- the per-language path regex, the
# header wording -- stays in the gate, where it belongs.

# qg_changed_files <base_ref>
# Union of: committed (<base>...HEAD), staged, and unstaged worktree changes.
# All three matter: a gate that only looked at commits would pass a dirty tree
# the developer is about to push.
qg_changed_files() {
  local base_ref="$1"
  local committed staged worktree
  git fetch origin --quiet 2>/dev/null || true
  committed=$(git diff --name-only "${base_ref}...HEAD" 2>/dev/null || true)
  staged=$(git diff --cached --name-only 2>/dev/null || true)
  worktree=$(git diff --name-only 2>/dev/null || true)
  printf '%s\n%s\n%s\n' "$committed" "$staged" "$worktree" | sort -u | sed '/^$/d'
}
