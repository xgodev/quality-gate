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

@test "measure_lint_and_complexity: ONE clippy pass, not two (#18)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir stubdir
  logdir=$(qg_tmp_dir)
  stubdir=$(qg_tmp_dir)
  # A cargo stub that records every invocation: the whole point of the fusion
  # is that lint+complexity cost a SINGLE clippy pass (a second one recompiles
  # the workspace -- cargo's fingerprint includes CLIPPY_ARGS).
  cat > "$stubdir/cargo" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$QG_STUB_CALLS"
exit 0
STUB
  chmod +x "$stubdir/cargo"
  QG_STUB_CALLS="$logdir/calls.txt" PATH="$stubdir:$PATH" \
    measure_lint_and_complexity "$(qg_fixture_path rust baseline)" \
      "$logdir/lint.log" "$logdir/cx.log" >/dev/null
  [ "$(grep -c clippy "$logdir/calls.txt")" = "1" ]
  rm -rf "$logdir" "$stubdir"
}

@test "measure_lint_and_complexity: same numbers as the two separate passes, baseline (#18)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir fixture
  logdir=$(qg_tmp_dir)
  fixture=$(qg_fixture_path rust baseline)
  expected_lint=$(count_lint_errors "$fixture" "$logdir/old-lint.log")
  expected_cx=$(count_complexity "$fixture" "$logdir/old-cx.log")
  result=$(measure_lint_and_complexity "$fixture" "$logdir/lint.log" "$logdir/cx.log")
  [ "$(echo "$result" | awk '{print $1}')" = "$expected_lint" ]
  [ "$(echo "$result" | awk '{print $2}')" = "$expected_cx" ]
  rm -rf "$logdir"
}

@test "measure_lint_and_complexity: same numbers as the two separate passes, regressed (#18)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir fixture
  logdir=$(qg_tmp_dir)
  fixture=$(qg_fixture_path rust regressed)
  expected_lint=$(count_lint_errors "$fixture" "$logdir/old-lint.log")
  expected_cx=$(count_complexity "$fixture" "$logdir/old-cx.log")
  result=$(measure_lint_and_complexity "$fixture" "$logdir/lint.log" "$logdir/cx.log")
  [ "$expected_lint" -gt 0 ]
  [ "$expected_cx" -gt 0 ]
  [ "$(echo "$result" | awk '{print $1}')" = "$expected_lint" ]
  [ "$(echo "$result" | awk '{print $2}')" = "$expected_cx" ]
  rm -rf "$logdir"
}

@test "measure_lint_and_complexity: writes the complexity log the docs point at (#18)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  measure_lint_and_complexity "$(qg_fixture_path rust regressed)" \
    "$logdir/lint.log" "$logdir/cx.log" >/dev/null
  [ -s "$logdir/cx.log" ]
  grep -qE 'cognitive complexity|too many lines|too many arguments|type complexity' "$logdir/cx.log"
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

@test "--quick: coverage is reported as skipped, not measured (#18)" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path rust baseline)"
  run --separate-stderr bash "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full \
    --quick
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.quick == true'
  echo "$output" | jq -e '.schema_version == "1.2"'
  # Rust defers coverage ONLY: complexity rides the lint clippy pass, so
  # deferring it would discard a number the gate measured anyway.
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "skipped") | .name] == ["coverage"]'
  echo "$output" | jq -e '.metrics[] | select(.name == "complexity") | .verdict != "skipped" and (.pr | type) == "number"'
  # A skipped metric carries NO numbers -- it was never measured.
  echo "$output" | jq -e '.metrics[] | select(.name == "coverage") | .base == null and .pr == null and .delta == null and .margin == null'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "--quick: a regression in a measured metric still fails (#18)" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path rust regressed)"
  run --separate-stderr bash "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full \
    --quick
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "regressed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "regressed") | .name] | index("lint") != null'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "--quick: no instrumented coverage run (#18)" {
  source "$QG_REPO_ROOT/lib/quick.sh"
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir stubdir
  logdir=$(qg_tmp_dir)
  stubdir=$(qg_tmp_dir)
  cat > "$stubdir/cargo" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$QG_STUB_CALLS"
exit 0
STUB
  chmod +x "$stubdir/cargo"
  QG_STUB_CALLS="$logdir/calls.txt" PATH="$stubdir:$PATH" \
    count_test_failures "$(qg_fixture_path rust baseline)" "$logdir/test.log" >/dev/null
  # The whole point of deferring coverage: no `cargo llvm-cov`, which is a
  # second instrumented build plus a second test run.
  ! grep -q 'llvm-cov' "$logdir/calls.txt"
  grep -q 'test' "$logdir/calls.txt"
  rm -rf "$logdir" "$stubdir"
}

@test "--quick never writes the base-metrics cache (it would fake a baseline) (#18)" {
  command -v cargo >/dev/null || skip "cargo not available"
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path rust baseline)/." "$repo/"
  cd "$repo"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  echo '// touch' >> src/lib.rs && git add -A && git commit -qm change
  cache_root="$repo/.qg-cache"
  QG_BASELINE_CACHE_DIR="$cache_root" run bash "$QG_REPO_ROOT/rust/qg.sh" --base main --force-full --quick --log-dir "$repo/logs1"
  # The second run is a FULL one: it must measure the base itself, not inherit
  # the quick run's zeros for complexity/coverage.
  QG_BASELINE_CACHE_DIR="$cache_root" run bash "$QG_REPO_ROOT/rust/qg.sh" --base main --force-full --log-dir "$repo/logs2"
  ! printf '%s' "$output" | grep -q 'base metrics: cached'
  cd / && rm -rf "$repo"
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

@test "measure_test_and_coverage: ONE run yields failures AND coverage (perf fusion)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_test_and_coverage "$(qg_fixture_path rust regressed)" "$logdir/test.log" "$logdir/cov.json")
  fails=$(echo "$result" | awk '{print $1}')
  cov=$(echo "$result" | awk '{print $2}')
  [ "$fails" -ge 1 ]                                   # test_failing_on_purpose detected
  awk -v c="$cov" 'BEGIN { exit !(c > 0 && c < 100) }' # coverage measured in the same run
  grep -qE 'test result:' "$logdir/test.log"           # test output captured for analysis
  rm -rf "$logdir"
}

@test "comparative: base metrics are cached by base SHA (second run skips base measurement)" {
  command -v cargo >/dev/null || skip "cargo not available"
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path rust baseline)/." "$repo/"
  cd "$repo"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  echo '// touch' >> src/lib.rs && git add -A && git commit -qm change
  cache_root="$repo/.qg-cache"
  QG_BASELINE_CACHE_DIR="$cache_root" run bash "$QG_REPO_ROOT/rust/qg.sh" --base main --force-full --log-dir "$repo/logs1"
  QG_BASELINE_CACHE_DIR="$cache_root" run bash "$QG_REPO_ROOT/rust/qg.sh" --base main --force-full --log-dir "$repo/logs2"
  printf '%s' "$output" | grep -q 'base metrics: cached'
  cd / && rm -rf "$repo"
}

# --- issue 17: diff-scoped cargo metrics -------------------------------------

_scope_ws() { echo "$QG_REPO_ROOT/rust/test-fixtures/workspace"; }

@test "scope: a change confined to a leaf crate scopes to that crate only" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  run qg_rust_scope "$(_scope_ws)" "crates/leaf/src/lib.rs"
  [ "$status" -eq 0 ]
  [ "$output" = "qgfix-leaf" ]
}

@test "scope: a change in a base crate pulls in its in-workspace reverse-dependents" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  run qg_rust_scope "$(_scope_ws)" "crates/core/src/lib.rs"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^qgfix-core$'
  echo "$output" | grep -q '^qgfix-mid$'
  echo "$output" | grep -q '^qgfix-leaf$'
  # an unrelated crate is never dragged in -- that is the whole point of the issue
  ! echo "$output" | grep -q 'qgfix-unrelated'
}

@test "scope: Cargo.lock forces full-workspace measurement" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  run qg_rust_scope "$(_scope_ws)" "Cargo.lock"
  [ "$output" = "__FULL__" ]
}

@test "scope: root manifest and toolchain pin force full-workspace measurement" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  run qg_rust_scope "$(_scope_ws)" "Cargo.toml"
  [ "$output" = "__FULL__" ]
  run qg_rust_scope "$(_scope_ws)" "rust-toolchain.toml"
  [ "$output" = "__FULL__" ]
  run qg_rust_scope "$(_scope_ws)" ".cargo/config.toml"
  [ "$output" = "__FULL__" ]
}

@test "scope: a member manifest scopes to that member, not the whole workspace" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  run qg_rust_scope "$(_scope_ws)" "crates/unrelated/Cargo.toml"
  [ "$output" = "qgfix-unrelated" ]
}

@test "scope: cargo package flags are emitted one -p per package" {
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  run qg_rust_pkg_flags "$(printf 'a\nb\n')"
  [ "$output" = "-p a -p b" ]
  run qg_rust_pkg_flags "__FULL__"
  [ "$output" = "--workspace" ]
}

@test "scope: baseline scope is the intersection with packages that exist on base" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  # qgfix-brandnew exists only in the PR tree -> must not be passed to the baseline
  run qg_rust_intersect_scope "$(_scope_ws)" "$(printf 'qgfix-leaf\nqgfix-brandnew\n')"
  [ "$output" = "qgfix-leaf" ]
}

@test "scope: base metrics cache key differs between full and narrow scope" {
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  full=$(qg_rust_scope_hash "__FULL__")
  narrow=$(qg_rust_scope_hash "$(printf 'qgfix-leaf\n')")
  [ -n "$full" ]
  [ -n "$narrow" ]
  [ "$full" != "$narrow" ]
}

@test "scope: resolves through a symlinked working dir (macOS /var -> /private/var)" {
  command -v cargo >/dev/null || skip "cargo not available"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  # mktemp on macOS lives under /var, a symlink to /private/var: the canonical
  # manifest_path from cargo would not prefix-match a logical pwd. Regression
  # for the scope block silently falling back to __FULL__ on any symlinked path.
  ws=$(qg_tmp_dir)
  cp -R "$QG_REPO_ROOT/rust/test-fixtures/workspace/." "$ws/"
  rm -f "$ws/Cargo.lock"
  run qg_rust_scope "$ws" "crates/leaf/src/lib.rs"
  [ "$status" -eq 0 ]
  [ "$output" = "qgfix-leaf" ]
  rm -rf "$ws"
}

@test "e2e: a leaf-only change scopes the gate to that crate, never the workspace" {
  command -v cargo >/dev/null || skip "cargo not available"
  ws=$(qg_tmp_dir)
  cp -R "$QG_REPO_ROOT/rust/test-fixtures/workspace/." "$ws/"
  cd "$ws"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  printf '\npub fn extra() -> u32 { 1 }\n' >> crates/leaf/src/lib.rs
  git add -A && git commit -qm 'change leaf only'
  QG_BASELINE_CACHE_DIR="$ws/.qgc" run bash "$QG_REPO_ROOT/rust/qg.sh" --base main --log-dir "$ws/logs"
  # scope must be the leaf crate, and the run must not report full-workspace
  printf '%s\n' "$output" | grep -q 'qgfix-leaf'
  ! printf '%s\n' "$output" | grep -q 'full workspace'
  # the unrelated crate must never have been built by the gate
  ! grep -rq 'qgfix-unrelated' "$ws/logs" 2>/dev/null
  cd "$QG_REPO_ROOT"; rm -rf "$ws"
}

# --- crate layout: codegen_mix + crate_size (#26) -----------------------------

_layout_ws() { echo "$QG_REPO_ROOT/rust/test-fixtures/layout"; }

_layout_libs() {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  source "$QG_REPO_ROOT/rust/lib/scope.sh"
  source "$QG_REPO_ROOT/rust/lib/layout.sh"
}

# A ruleset copy with a tiny threshold, so the fixtures stay small. This is the
# ONLY supported override (QG_RULESET_DIR, set by whoever runs the gate).
_layout_rules_max() {
  local dir
  dir=$(qg_tmp_dir)
  cp "$QG_REPO_ROOT/rust/rules/"*.toml "$dir/" 2>/dev/null || true
  sed -i.bak -E "s/^max_hand_written_lines = .*/max_hand_written_lines = $1/" "$dir/crate-layout.toml"
  rm -f "$dir/crate-layout.toml.bak"
  echo "$dir"
}

@test "layout: a codegen-only crate (lib.rs just includes the output) is not a mix (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  run qg_rust_layout_table "$(_layout_ws)"
  [ "$status" -eq 0 ]
  # codegen = 1, non-include-only lines = 0 -> not counted
  echo "$output" | grep -qE '^qglayout-codegen-only\tcrates/codegen-only\t[0-9]+\t0\t1$'
}

@test "layout: a crate mixing build.rs codegen with hand-written modules is counted (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local logdir
  logdir=$(qg_tmp_dir)
  run count_codegen_mix "$(_layout_ws)" "$logdir/mix.log"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  # and the fused scan names the offending crate, so the dev knows what to split
  measure_layout "$(_layout_ws)" "$logdir/layout.log" >/dev/null
  grep -q 'codegen_mix: crate qglayout-codegen-mixed' "$logdir/layout.log"
  rm -rf "$logdir"
}

@test "layout: crate_size counts only the lines ABOVE the threshold (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local rules
  rules=$(_layout_rules_max 20)
  # grown holds 30 hand-written lines -> 10 over; every other crate is under.
  QG_RULESET_DIR="$rules" run count_crate_size "$(_layout_ws)"
  [ "$output" = "10" ]
  # at the shipped threshold nothing is over the line
  run count_crate_size "$(_layout_ws)"
  [ "$output" = "0" ]
  rm -rf "$rules"
}

@test "layout: a crate already over the threshold that does not grow does NOT regress (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  source "$QG_REPO_ROOT/rust/lib/output.sh"
  local rules base pr
  rules=$(_layout_rules_max 20)
  base=$(qg_tmp_dir); pr=$(qg_tmp_dir)
  cp -R "$(_layout_ws)/." "$base/"
  cp -R "$(_layout_ws)/." "$pr/"
  local b p
  b=$(QG_RULESET_DIR="$rules" count_crate_size "$base")
  p=$(QG_RULESET_DIR="$rules" count_crate_size "$pr")
  [ "$(verdict_count "$b" "$p")" = "same" ]
  # growing the crate that is ALREADY over the line regresses it
  printf '\npub fn extra() -> u32 {\n    1\n}\n' >> "$pr/crates/grown/src/lib.rs"
  p=$(QG_RULESET_DIR="$rules" count_crate_size "$pr")
  [ "$(verdict_count "$b" "$p")" = "regressed" ]
  rm -rf "$rules" "$base" "$pr"
}

@test "layout: a crate CROSSING the threshold regresses (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  source "$QG_REPO_ROOT/rust/lib/output.sh"
  local rules base pr b p
  # 8 lines: `small` (6 lines) is under, and crosses once the PR adds to it.
  rules=$(_layout_rules_max 8)
  base=$(qg_tmp_dir); pr=$(qg_tmp_dir)
  cp -R "$(_layout_ws)/." "$base/"
  cp -R "$(_layout_ws)/." "$pr/"
  printf '\npub fn three() -> u32 {\n    3\n}\n' >> "$pr/crates/small/src/lib.rs"
  b=$(QG_RULESET_DIR="$rules" qg_rust_layout_table "$base" | awk -F'\t' '$1 == "qglayout-small" { print $3 }')
  p=$(QG_RULESET_DIR="$rules" qg_rust_layout_table "$pr" | awk -F'\t' '$1 == "qglayout-small" { print $3 }')
  [ "$b" -le 8 ]
  [ "$p" -gt 8 ]
  b=$(QG_RULESET_DIR="$rules" count_crate_size "$base")
  p=$(QG_RULESET_DIR="$rules" count_crate_size "$pr")
  [ "$(verdict_count "$b" "$p")" = "regressed" ]
  rm -rf "$rules" "$base" "$pr"
}

@test "layout: tests/, benches/, examples/, build.rs and #[cfg(test)] mods are not crate weight (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local n
  # `grown` holds 10 three-line fns = 30 lines, plus a #[cfg(test)] module, a
  # @generated src/api.rs, tests/it.rs, benches/bench.rs and examples/demo.rs --
  # each of which is its OWN compilation unit, so none of them is crate weight.
  n=$(qg_rust_layout_table "$(_layout_ws)" | awk -F'\t' '$1 == "qglayout-grown" { print $3 }')
  [ "$n" -eq 30 ]
}

@test "layout: a file the language marks as generated is not hand-written (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local tmp n
  tmp=$(qg_tmp_dir)
  cp -R "$(_layout_ws)/." "$tmp/"
  n=$(qg_rust_layout_table "$tmp" | awk -F'\t' '$1 == "qglayout-grown" { print $3 }')
  # dropping the @generated marker makes the same file count
  sed -i.bak '1d' "$tmp/crates/grown/src/api.rs" && rm -f "$tmp/crates/grown/src/api.rs.bak"
  local n2
  n2=$(qg_rust_layout_table "$tmp" | awk -F'\t' '$1 == "qglayout-grown" { print $3 }')
  [ "$n2" -gt "$n" ]
  rm -rf "$tmp"
}

@test "layout: a nested member owns its own lines, the parent crate never inherits them (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local table
  table=$(qg_rust_layout_table "$(_layout_ws)")
  # crates/grown/nested is a member inside crates/grown: longest-prefix wins.
  [ "$(printf '%s\n' "$table" | awk -F'\t' '$1 == "qglayout-nested" { print $3 }')" -eq 3 ]
  [ "$(printf '%s\n' "$table" | awk -F'\t' '$1 == "qglayout-grown" { print $3 }')" -eq 30 ]
}

@test "layout LAW tamper: a project file cannot raise the crate-size threshold (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local tmp
  tmp=$(qg_tmp_dir)
  cp -R "$(_layout_ws)/." "$tmp/"
  # The dev controls these; a raised threshold would switch the check off.
  cat > "$tmp/.qg.yaml" <<EOF
max_hand_written_lines: 999999
EOF
  cat > "$tmp/crate-layout.toml" <<EOF
max_hand_written_lines = 999999
EOF
  mkdir -p "$tmp/rules"
  cp "$tmp/crate-layout.toml" "$tmp/rules/crate-layout.toml"
  cd "$tmp"
  run qg_layout_max_lines
  [ "$output" = "5000" ]
  cd "$QG_REPO_ROOT"
  # the ONLY override is the env var supplied by whoever RUNS the gate
  local rules
  rules=$(_layout_rules_max 20)
  QG_RULESET_DIR="$rules" run qg_layout_max_lines
  [ "$output" = "20" ]
  rm -rf "$tmp" "$rules"
}

@test "layout LAW tamper: the codegen signatures come from the QG ruleset, not the project (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  run qg_layout_codegen_re
  [ "$status" -eq 0 ]
  [[ "$output" == *"slint_build::"* ]]
  [[ "$output" == *"prost_build"* ]]
  [[ "$output" == *"bindgen::"* ]]
}

@test "layout: the fused scan reports exactly what the single-metric oracles report (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  _layout_libs
  local rules logdir fused mix size
  rules=$(_layout_rules_max 20)
  logdir=$(qg_tmp_dir)
  fused=$(QG_RULESET_DIR="$rules" measure_layout "$(_layout_ws)" "$logdir/fused.log")
  mix=$(QG_RULESET_DIR="$rules" count_codegen_mix "$(_layout_ws)")
  size=$(QG_RULESET_DIR="$rules" count_crate_size "$(_layout_ws)")
  [ "$fused" = "$mix $size" ]
  rm -rf "$rules" "$logdir"
}

@test "layout: an unenumerable workspace is a tool-error, never a metric of 0 (#26)" {
  _layout_libs
  local tmp
  tmp=$(qg_tmp_dir)
  # No Cargo.toml at all: `cargo metadata` fails, the member list is empty. A 0
  # on one side only would read as a regression, so the caller must exit 2.
  run qg_rust_layout_table "$tmp"
  [ "$status" -eq 1 ]
  run measure_layout "$tmp" "$tmp/layout.log"
  [ "$status" -eq 1 ]
  rm -rf "$tmp"
}

@test "layout: both metrics reach the comparative JSON with numbers (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path rust baseline)"
  run --separate-stderr bash "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.metrics[] | select(.name == "codegen_mix") | (.base|type) == "number" and (.pr|type) == "number"'
  echo "$output" | jq -e '.metrics[] | select(.name == "crate_size") | (.base|type) == "number" and (.pr|type) == "number"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "layout: --quick still measures both metrics -- a file scan saves nothing by deferring (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path rust baseline)"
  run --separate-stderr bash "$(qg_script_path rust)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path rust baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full \
    --quick
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "skipped") | .name] == ["coverage"]'
  echo "$output" | jq -e '.metrics[] | select(.name == "codegen_mix") | .verdict != "skipped" and (.pr|type) == "number"'
  echo "$output" | jq -e '.metrics[] | select(.name == "crate_size") | .verdict != "skipped" and (.pr|type) == "number"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "layout: both metrics reach the absolute JSON and honor absolute_thresholds (#26)" {
  command -v cargo >/dev/null || skip "cargo not available"
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path rust baseline)/." "$tmp/"
  cd "$tmp"
  run --separate-stderr bash "$(qg_script_path rust)" --log-dir "$logdir" --format json
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.metrics[] | select(.name == "codegen_mix") | (.value|type) == "number"'
  echo "$output" | jq -e '.metrics[] | select(.name == "crate_size") | (.value|type) == "number"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}
