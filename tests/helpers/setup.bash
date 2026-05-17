#!/usr/bin/env bash
# Shared helpers for the Quality Gate bats tests.

# Repo root path (assumes tests/ is at the root)
QG_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QG_REPO_ROOT

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
