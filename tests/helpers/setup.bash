#!/usr/bin/env bash
# Shared helpers for the Quality Gate bats tests.

# Quality-gate root (tools/quality-gate -- holds qg and the <lang>/ dirs)
QG_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QG_REPO_ROOT

# Actual repository root (holds hooks/, skills/, docs/)
QG_GIT_ROOT="$(cd "$QG_REPO_ROOT/../.." && pwd)"
export QG_GIT_ROOT

# Path of a language's script
qg_script_path() {
  local lang="$1"
  echo "$QG_REPO_ROOT/$lang/qg.sh"
}

# Path of a fixture
qg_fixture_path() {
  local lang="$1"
  local kind="$2"  # baseline or regressed
  echo "$QG_REPO_ROOT/$lang/test-fixtures/$kind"
}

# Temporary directory for this test run
qg_tmp_dir() {
  mktemp -d -t qg-test-XXXXXX
}

# Clears the gate's env vars (avoids cross-test contamination)
qg_clean_env() {
  unset QG_BYPASS_REASON QG_BASE_REF QG_BASELINE_DIR QG_COV_MARGIN \
        QG_LOG_DIR QG_REFRESH_BASELINE QG_FORCE_FULL QG_FORMAT
}

# --- pre-push hook helpers -------------------------------------------------
qg_hook_path() {
  echo "$QG_GIT_ROOT/hooks/quality-gate/pr-gate.sh"
}

# Makes a temp "plugin root" holding a qg stub (at the bundled path
# tools/quality-gate/qg) that exits with RC and echoes its args to
# stderr (so tests can assert --base forwarding).
qg_make_stub_plugin() {
  local rc="$1"
  local d
  d="$(mktemp -d -t qg-plugin-XXXXXX)"
  mkdir -p "$d/tools/quality-gate"
  cat > "$d/tools/quality-gate/qg" <<EOF
#!/usr/bin/env bash
echo "stub-qg-args: \$*" >&2
exit $rc
EOF
  chmod +x "$d/tools/quality-gate/qg"
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
