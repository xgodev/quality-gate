#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "python/qg.sh --help shows usage" {
  run "$(qg_script_path python)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "python/qg.sh -h equivalent to --help" {
  run "$(qg_script_path python)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "python/qg.sh declares QG_CONTRACT_VERSION=1 in the header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path python)"
  [ "$status" -eq 0 ]
}

@test "python/qg.sh without --base does NOT exit 2 due to missing --base (absolute mode)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path python)"
  [[ "$output" != *"--base is required"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python/qg.sh respects the QG_BASE_REF env var when --base is absent" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path python)"
  [[ "$output" != *"--base is required"* ]]
}

@test "python/qg.sh --detect without a sentinel exits 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path python)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python/qg.sh --detect with a sentinel prints the slug and exits 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "[project]" > pyproject.toml
  run "$(qg_script_path python)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "python" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python LAW: poetry.lock present but poetry off PATH = tool-error, no pip" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/pyproject.toml" <<EOF
[tool.poetry]
name = "x"
version = "0.1.0"
EOF
  echo "# lockfile fake" > "$tmp/poetry.lock"
  # Stub: fails the test if 'pip' is invoked (silent substitution).
  local stubdir="$logdir/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/pip" <<EOF
#!/usr/bin/env bash
echo "PIP-FOI-INVOCADO" >> "$logdir/pip-called"
exit 0
EOF
  chmod +x "$stubdir/pip"
  # PATH without poetry; pip stub present but must NOT be used.
  run env PATH="$stubdir:/usr/bin:/bin" "$(command -v bash)" -c "source '$QG_REPO_ROOT/python/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'poetry.lock' "$logdir/abs-deps.log"
  grep -q 'poetry' "$logdir/abs-deps.log"
  [ ! -f "$logdir/pip-called" ]
  rm -rf "$tmp" "$logdir"
}

@test "python LAW: uv.lock without uv = clear tool-error" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "[project]" > "$tmp/pyproject.toml"
  echo "# uv lock" > "$tmp/uv.lock"
  local emptydir="$logdir/emptybin"
  mkdir -p "$emptydir"
  run env PATH="$emptydir" "$(command -v bash)" -c "source '$QG_REPO_ROOT/python/lib/measure.sh'; qg_resolve_lock_manager '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'uv.lock' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "python LAW: requirements.txt without a manager lockfile -> legitimate pip (no tool-error)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "" > "$tmp/requirements.txt"
  local rc=0
  qg_resolve_lock_manager "$tmp" "$logdir/abs-deps.log" || rc=$?
  [ "$rc" -eq 2 ]
  [ ! -s "$logdir/abs-deps.log" ]
  rm -rf "$tmp" "$logdir"
}

@test "python/qg.sh absolute mode without .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path python baseline)"
  run --separate-stderr "$(qg_script_path python)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "python/qg.sh absolute mode with absolute_thresholds violated: exit 1, metric violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path python regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path python)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "Bug 2: undefined coverage becomes 0, valid JSON, gate does not break (absolute mode)" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  # Python project without tests -> undefined coverage.
  cat > pyproject.toml <<EOF
[project]
name = "x"
version = "0.1.0"
EOF
  cat > mod.py <<EOF
def add(a, b):
    return a + b
EOF
  run --separate-stderr "$(qg_script_path python)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
  echo "$output" | jq -e '(.metrics[] | select(.name=="coverage") | .value) == 0'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "python/qg.sh --format invalid exits 2" {
  run "$(qg_script_path python)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "python/qg.sh --cov-margin non-numeric exits 2" {
  run "$(qg_script_path python)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "python/qg.sh detects a missing tool and exits 2 with an installable message" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path python)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"python"* ]]
  [[ "$output" == *"install"* ]]
}

@test "python/qg.sh with QG_BYPASS_REASON exits 0 and emits a warning" {
  export QG_BYPASS_REASON="bypass test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path python)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"bypass test"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "bypass test" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "python/qg.sh with QG_BYPASS_REASON --format json returns verdict bypassed" {
  export QG_BYPASS_REASON="test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path python)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "test"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "python/qg.sh fast-path when only docs changed" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "# test" > README.md
  git add README.md
  git commit -qm "initial"
  git checkout -qb feature
  echo "new content" >> README.md
  git add README.md
  git commit -qm "edit docs"

  run "$(qg_script_path python)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "" == *"no "* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python/qg.sh --force-full skips fast-path" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "# test" > README.md
  git add README.md
  git commit -qm "initial"
  git checkout -qb feature
  echo "edit" >> README.md
  git add README.md
  git commit -qm "edit"

  run "$(qg_script_path python)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir nonexistent exits 2" {
  run "$(qg_script_path python)" --base origin/main --baseline-dir /tmp/qg-py-does-not-exist-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: language absent in baseline emits a warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem pyproject.toml" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > pyproject.toml <<EOF
[project]
name = "x"
version = "0.1.0"
EOF
  echo "x = 1" > x.py
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "# edit" >> x.py
  git add . && git commit -qm "edit"

  run "$(qg_script_path python)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"language absent"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 in the baseline fixture" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path python baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 in the regressed fixture" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path python regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 in baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path python baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 in regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path python regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 in baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path python baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 in baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path python baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 in regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path python regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 in baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path python baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 in regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path python regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: 100% in baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path python baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% in regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path python regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: running regressed against baseline -> exit 1, JSON with verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path python regressed)"
  run --separate-stderr "$(qg_script_path python)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path python baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "regressed"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: running baseline against itself -> exit 0" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path python baseline)"
  run --separate-stderr "$(qg_script_path python)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path python baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "passed"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: --format text shows the table with expected columns" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path python baseline)"
  run "$(qg_script_path python)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path python baseline)" \
    --log-dir "$logdir" \
    --format text \
    --force-full
  [ "$status" -eq 0 ]
  [[ "$output" == *"metric"* ]]
  [[ "$output" == *"verdict"* ]]
  [[ "$output" == *"fmt"* ]]
  [[ "$output" == *"coverage"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: 10 identical runs in regressed must return exit 1 every time" {
  for i in $(seq 1 10); do
    local logdir
    logdir=$(qg_tmp_dir)
    cd "$(qg_fixture_path python regressed)"
    run "$(qg_script_path python)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path python baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "Bug build/: lint/complexity/fmt ignore generated dirs (measures source, not artifact)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  # src/ real LIMPO: formatado, sem lint/complexity.
  mkdir -p "$tmp/src"
  cat > "$tmp/src/clean.py" <<'EOF'
def add(a, b):
    return a + b
EOF
  # build/ + dist/ GENERATED: Python junk with an unused import (F401),
  # formatacao ruim e funcao de alta complexidade.
  mkdir -p "$tmp/build/lib" "$tmp/dist"
  cat > "$tmp/build/lib/generated.py" <<'EOF'
import os,sys
def f(x):
 if x>0:
  if x>1:
   if x>2:
    if x>3:
     if x>4:
      if x>5:
       if x>6:
        return undefined_thing
EOF
  cp "$tmp/build/lib/generated.py" "$tmp/dist/bundle.py"
  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_cx=$(count_complexity "$tmp" "$logdir/cx.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  [ "$result_lint" = "0" ] || { echo "lint should be 0 (build/dist ignored); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_cx" = "0" ] || { echo "complexity should be 0 (build/dist ignored); got $result_cx"; cat "$logdir/cx.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "fmt should be 0 (only clean src/); got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/ tamper: empty project .gitignore does NOT loosen -- QG excludes build/ via the canonical ignore" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  # Dev tries to force scanning everything: .gitignore EMPTY.
  : > "$tmp/.gitignore"
  mkdir -p "$tmp/src" "$tmp/build"
  cat > "$tmp/src/ok.py" <<'EOF'
def ok():
    return 1
EOF
  cat > "$tmp/build/gen.py" <<'EOF'
import os,sys,json
def bad( ):
    return undefined
EOF
  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  # QG ruff.toml extend-exclude does not depend on respect-gitignore ->
  # build/ excluido mesmo com .gitignore vazio.
  [ "$result_lint" = "0" ] || { echo "tamper: lint should be 0 (QG extend-exclude); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "tamper: fmt should be 0; got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/: REAL violation in src/ still counted (the exclusion does not mask source)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  mkdir -p "$tmp/src" "$tmp/build"
  cat > "$tmp/src/bad.py" <<'EOF'
import os
def f():
    return 1
EOF
  cat > "$tmp/build/gen.py" <<'EOF'
import sys
def g():
    return 2
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  [ "$result" -gt 0 ] || { echo "expected >0 (real F401 in src/); got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "tamper-resistance: ruff ignores the project's loosened config (gate uses QG's ruleset)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path python regressed)/." "$tmp/"
  # Dev tries to loosen: pyproject.toml turns off F401 (unused import).
  cat > "$tmp/pyproject.toml" <<EOF
[tool.ruff.lint]
ignore = ["F401", "E", "F", "W", "I"]
[tool.ruff]
line-length = 999
EOF
  cat > "$tmp/ruff.toml" <<EOF
[lint]
ignore = ["F401", "E", "F", "W", "I"]
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Gate ignores the loosened config (--isolated --config QG) and still flags F401.
  [ "$result" -gt 0 ] || { echo "expected >0 even with a loosened config; got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "baseline: _qg_extract_submodules populates submodules at the base-ref commit (issue #2)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local sub super target c1
  sub=$(qg_tmp_dir); super=$(qg_tmp_dir); target=$(qg_tmp_dir)

  # Submodule repo: v1 ships a source file the superproject build globs; v2 changes it.
  cd "$sub"
  git -c init.defaultBranch=main init -q
  git config user.email t@t; git config user.name T
  mkdir NAM; echo 'int a(){return 0;}' > NAM/core.cpp
  git add . && git commit -qm v1
  c1=$(git rev-parse HEAD)
  echo '// v2 change' >> NAM/core.cpp
  git add . && git commit -qm v2

  # Superproject pins the submodule at v1 (NOT the tip).
  cd "$super"
  git -c init.defaultBranch=main init -q
  git config user.email t@t; git config user.name T
  echo root > root.txt
  git -c protocol.file.allow=always submodule add -q "$sub" deps/core
  git -C deps/core checkout -q "$c1"
  git add . && git commit -qm super-v1

  # Emulate prepare_baseline's `git archive` step (does NOT expand submodules).
  git archive HEAD | tar -xC "$target"
  [ ! -e "$target/deps/core/NAM/core.cpp" ]   # precondition: archive left the submodule empty

  # The fix under test.
  _qg_extract_submodules "$(git rev-parse --absolute-git-dir)" HEAD "$target" "$(git rev-parse --show-toplevel)"

  [ -f "$target/deps/core/NAM/core.cpp" ]      # submodule source is now present
  run cat "$target/deps/core/NAM/core.cpp"
  [[ "$output" == *"int a()"* ]]
  [[ "$output" != *"v2 change"* ]]             # pinned to the base-ref commit (v1), not the submodule tip

  cd "$QG_REPO_ROOT"
  rm -rf "$sub" "$super" "$target"
}

@test "baseline: _qg_extract_submodules is a no-op for a repo without submodules (issue #2)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local plain target
  plain=$(qg_tmp_dir); target=$(qg_tmp_dir)
  cd "$plain"
  git -c init.defaultBranch=main init -q
  git config user.email t@t; git config user.name T
  echo hi > a.txt
  git add . && git commit -qm init
  git archive HEAD | tar -xC "$target"
  run _qg_extract_submodules "$(git rev-parse --absolute-git-dir)" HEAD "$target" "$(git rev-parse --show-toplevel)"
  [ "$status" -eq 0 ]
  cd "$QG_REPO_ROOT"
  rm -rf "$plain" "$target"
}
