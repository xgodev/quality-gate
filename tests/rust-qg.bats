#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "rust/qg.sh --help shows usage" {
  run "$(qg_script_path rust)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "rust/qg.sh -h equivalent to --help" {
  run "$(qg_script_path rust)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "rust/qg.sh declares QG_CONTRACT_VERSION=1 in the header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path rust)"
  [ "$status" -eq 0 ]
}

@test "rust/qg.sh without --base does NOT exit 2 due to missing --base (absolute mode)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path rust)"
  [[ "$output" != *"--base is required"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust/qg.sh respects the QG_BASE_REF env var when --base is absent" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path rust)"
  # Should not exit 2 due to missing --base; may exit 2 for other reasons later.
  [[ "$output" != *"--base is required"* ]]
}

@test "rust/qg.sh --detect without a sentinel exits 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path rust)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust/qg.sh --detect with a sentinel prints the slug and exits 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  cat > Cargo.toml <<EOF
[package]
name = "x"
version = "0.1.0"
edition = "2021"
EOF
  run "$(qg_script_path rust)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "rust" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust LAW: rust-toolchain.toml with a channel not installed and not installable = tool-error" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/Cargo.toml" <<EOF
[package]
name = "x"
version = "0.1.0"
edition = "2021"
EOF
  cat > "$tmp/rust-toolchain.toml" <<EOF
[toolchain]
channel = "nightly-2099-12-31"
EOF
  # Stub rustup: channel absent from the list and 'rustup run' fails (offline).
  local stubdir="$logdir/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/rustup" <<EOF
#!/usr/bin/env bash
case "\$1" in
  "toolchain") echo "stable-x86_64 (default)"; exit 0 ;;
  "run") exit 1 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$stubdir/rustup"
  run env PATH="$stubdir:/usr/bin:/bin" "$(command -v bash)" -c "source '$QG_REPO_ROOT/rust/lib/measure.sh'; qg_check_rust_toolchain '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'rust-toolchain' "$logdir/abs-deps.log"
  grep -q 'nightly-2099-12-31' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "rust LAW: script does NOT inject +stable/an override that ignores rust-toolchain.toml" {
  # Ignore comment lines (start with # after spaces): only real code.
  run bash -c "grep -vE '^[[:space:]]*#' '$QG_REPO_ROOT/rust/lib/measure.sh' | grep -nE 'cargo[[:space:]]+\+|rustup override set|--toolchain[[:space:]]+stable'"
  [ "$status" -ne 0 ]
}

@test "rust LAW: a channel already installed is NOT a tool-error" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/rust-toolchain.toml" <<EOF
[toolchain]
channel = "stable"
EOF
  local stubdir="$logdir/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/rustup" <<EOF
#!/usr/bin/env bash
[ "\$1" = "toolchain" ] && { echo "stable-x86_64-apple-darwin (default)"; exit 0; }
exit 0
EOF
  chmod +x "$stubdir/rustup"
  run env PATH="$stubdir:/usr/bin:/bin" "$(command -v bash)" -c "source '$QG_REPO_ROOT/rust/lib/measure.sh'; qg_check_rust_toolchain '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 0 ]
  [ ! -s "$logdir/abs-deps.log" ]
  rm -rf "$tmp" "$logdir"
}

@test "rust/qg.sh absolute mode without .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path rust baseline)"
  run --separate-stderr "$(qg_script_path rust)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "rust/qg.sh absolute mode with absolute_thresholds violated: exit 1, metric violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path rust regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path rust)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "rust _num: sanitizes non-numeric to 0 (Bug 2)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "82.3")" = "82.3" ]
  [ "$(_num "7")" = "7" ]
}

@test "rust/qg.sh --format invalid exits 2" {
  run "$(qg_script_path rust)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "rust/qg.sh --cov-margin non-numeric exits 2" {
  run "$(qg_script_path rust)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "rust/qg.sh detects a missing tool and exits 2 with an installable message" {
  # Simulate PATH without cargo
  run env PATH="/usr/bin:/bin" "$(qg_script_path rust)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"cargo"* ]]
  [[ "$output" == *"install"* ]]
}

@test "rust/qg.sh with QG_BYPASS_REASON exits 0 and emits a warning" {
  export QG_BYPASS_REASON="bypass test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path rust)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"bypass test"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "bypass test" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "rust/qg.sh with QG_BYPASS_REASON --format json returns verdict bypassed" {
  export QG_BYPASS_REASON="test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path rust)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "test"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "rust/qg.sh without QG_BYPASS_REASON does not emit a bypass" {
  unset QG_BYPASS_REASON
  run "$(qg_script_path rust)" --base origin/main
  [[ "$output" != *"bypass"* ]]
}

@test "rust/qg.sh fast-path when only docs changed" {
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

  run "$(qg_script_path rust)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"no Rust"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust/qg.sh --force-full skips fast-path" {
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

  # --force-full should continue and eventually exit 2 (no Cargo.toml) or try to measure
  run "$(qg_script_path rust)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test ".qg.yaml invalid (unknown key) exits 2" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  cat > .qg.yaml <<EOF
unknown_key: 123
cov_margin: 2.0
EOF
  run "$(qg_script_path rust)" --base origin/main --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown_key"* ]] || [[ "$output" == *".qg.yaml"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test ".qg.yaml with numeric cov_margin is accepted" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "cov_margin: 3.5" > .qg.yaml
  run "$(qg_script_path rust)" --base origin/main --force-full
  # May exit 2 for other reasons (no git, no Cargo.toml) but NOT due to .qg.yaml
  [[ "$output" != *"unknown_key"* ]]
  [[ "$output" != *"unknown"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test ".qg.yaml skip_metrics without reason exits 2" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  cat > .qg.yaml <<EOF
skip_metrics:
  - metric: complexity
    until: "2026-09-01"
EOF
  run "$(qg_script_path rust)" --base origin/main --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"reason"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir nonexistent exits 2" {
  run "$(qg_script_path rust)" --base origin/main --baseline-dir /tmp/qg-does-not-exist-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: _qg_extract_submodules populates submodules at the base-ref commit (issue #2)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
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
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
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

@test "count_fmt: 0 in the baseline fixture" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path rust baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 in the regressed fixture" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path rust regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 in baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path rust baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 in regressed" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path rust regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 in baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path rust baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 in baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path rust baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 in regressed (test_failing_on_purpose)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path rust regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 in baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path rust baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 in regressed (complex_function)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path rust regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: ~100% in baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path rust baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% in regressed (uncovered exists)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path rust regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: running regressed against baseline -> exit 1, JSON with verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path rust regressed)"
  run --separate-stderr "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
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
  cd "$(qg_fixture_path rust baseline)"
  run --separate-stderr "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
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
  cd "$(qg_fixture_path rust baseline)"
  run "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
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
    cd "$(qg_fixture_path rust regressed)"
    run "$(qg_script_path rust)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path rust baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "baseline (default cache): stale/incomplete cache must NOT silently return passed+[] (issue #1)" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not available"
  local tmp cache backup
  tmp=$(qg_tmp_dir)
  cache="/tmp/qg-baseline-rust"
  backup=""
  if [ -e "$cache" ]; then
    backup="${cache}.bats-bk-$$"
    mv "$cache" "$backup"
  fi
  cd "$tmp"
  git -c init.defaultBranch=main init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > Cargo.toml <<EOF
[package]
name = "x"
version = "0.1.0"
edition = "2021"
[lib]
path = "src/lib.rs"
EOF
  mkdir src
  echo "pub fn x() {}" > src/lib.rs
  git add . && git commit -qm "init"
  rm -rf "$cache"
  mkdir -p "$cache"
  run "$(qg_script_path rust)" --base main --format json
  local rc=$status
  local out="$output"
  rm -rf "$cache"
  if [ -n "$backup" ]; then mv "$backup" "$cache"; fi
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
  ! echo "$out" | jq -e '.verdict == "passed" and (.metrics | length) == 0 and .duration_seconds == 0' >/dev/null 2>&1
}

@test "baseline: language absent in baseline emits a warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# no Cargo.toml" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > Cargo.toml <<EOF
[package]
name = "x"
version = "0.1.0"
edition = "2021"
[lib]
path = "src/lib.rs"
EOF
  mkdir src
  echo "pub fn x() {}" > src/lib.rs
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "// edit" >> src/lib.rs
  git add . && git commit -qm "edit"

  run "$(qg_script_path rust)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"language absent"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "tamper-resistance: clippy ignores the project's loosened clippy.toml (gate uses QG's ruleset)" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path rust regressed)/." "$tmp/"
  # Dev tries to loosen: the project's clippy.toml raises thresholds to infinity.
  cat > "$tmp/clippy.toml" <<EOF
cognitive-complexity-threshold = 99999
too-many-lines-threshold = 99999
too-many-arguments-threshold = 99999
type-complexity-threshold = 999999
EOF
  result=$(count_complexity "$tmp" "$logdir/cx.log")
  # Gate uses CLIPPY_CONF_DIR=<QG>/rust/rules (threshold 25), ignores the project's.
  [ "$result" -gt 0 ] || { echo "expected >0 even with a loosened clippy.toml; got $result"; cat "$logdir/cx.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
