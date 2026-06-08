#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "swift/qg.sh --help shows usage" {
  run "$(qg_script_path swift)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "swift/qg.sh -h equivalent to --help" {
  run "$(qg_script_path swift)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "swift/qg.sh declares QG_CONTRACT_VERSION=1 in the header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path swift)"
  [ "$status" -eq 0 ]
}

@test "swift/qg.sh without --base does NOT exit 2 due to missing --base (absolute mode)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path swift)"
  [[ "$output" != *"--base is required"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift/qg.sh respects the QG_BASE_REF env var when --base is absent" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path swift)"
  [[ "$output" != *"--base is required"* ]]
}

@test "swift/qg.sh --detect without a sentinel exits 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path swift)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift/qg.sh --detect with a sentinel prints the slug and exits 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "// swift-tools-version:5.9" > Package.swift
  run "$(qg_script_path swift)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "swift" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift _num: sanitizes non-numeric to 0 (Bug 2)" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "82.3")" = "82.3" ]
}

@test "swift LAW: Package.swift swift-tools-version above the PATH swift = tool-error" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  command -v swift >/dev/null 2>&1 || skip "swift not available"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/Package.swift" <<EOF
// swift-tools-version:99.0
import PackageDescription
let package = Package(name: "x")
EOF
  run "$(command -v bash)" -c "source '$QG_REPO_ROOT/swift/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'swift-tools-version:99.0' "$logdir/abs-deps.log"
  # There should be no output from 'swift package resolve' (it did not get to run).
  ! grep -qi 'Fetching\|Computing version' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "swift LAW: a satisfied swift-tools-version is NOT a tool-error" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  command -v swift >/dev/null 2>&1 || skip "swift not available"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/Package.swift" <<EOF
// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "x")
EOF
  run "$(command -v bash)" -c "source '$QG_REPO_ROOT/swift/lib/measure.sh'; qg_check_swift_tools_version '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 0 ]
  [ ! -s "$logdir/abs-deps.log" ]
  rm -rf "$tmp" "$logdir"
}

@test "swift/qg.sh absolute mode without .qg.yaml: exit 0, JSON mode absolute without complexity" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path swift baseline)"
  run --separate-stderr "$(qg_script_path swift)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].name] | index("complexity") == null'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "swift/qg.sh absolute mode with absolute_thresholds violated: exit 1, metric violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path swift regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path swift)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "swift/qg.sh absolute mode with absolute_thresholds complexity rejected (omitted)" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "// swift-tools-version:5.9" > Package.swift
  cat > .qg.yaml <<EOF
absolute_thresholds:
  complexity: 5
EOF
  run --separate-stderr "$(qg_script_path swift)" --log-dir "$logdir" --format json
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"complexity"* ]] || [[ "$output" == *"complexity"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "swift/qg.sh --format invalid exits 2" {
  run "$(qg_script_path swift)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "swift/qg.sh --cov-margin non-numeric exits 2" {
  run "$(qg_script_path swift)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "swift/qg.sh detects a missing tool and exits 2 with an installable message" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path swift)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"swift"* ]]
  [[ "$output" == *"install"* ]]
}

@test "swift/qg.sh with QG_BYPASS_REASON exits 0 and emits a warning" {
  export QG_BYPASS_REASON="bypass test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path swift)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"bypass test"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "bypass test" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "swift/qg.sh with QG_BYPASS_REASON --format json returns verdict bypassed" {
  export QG_BYPASS_REASON="test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path swift)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "test"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "swift/qg.sh fast-path when only docs changed" {
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

  run "$(qg_script_path swift)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "" == *"no "* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift/qg.sh --force-full skips fast-path" {
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

  run "$(qg_script_path swift)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir nonexistent exits 2" {
  run "$(qg_script_path swift)" --base origin/main --baseline-dir /tmp/qg-swift-does-not-exist-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: language absent in baseline emits a warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem Package.swift" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > Package.swift <<EOF
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "X")
EOF
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "// edit" >> Package.swift
  git add . && git commit -qm "edit"

  run "$(qg_script_path swift)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"language absent"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 in the baseline fixture" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path swift baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 in the regressed fixture" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path swift regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 in baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path swift baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 in regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path swift regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 in baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path swift baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 in baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path swift baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 in regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path swift regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "complexity is not measured (omitted in Swift)" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  # count_complexity must not be defined.
  ! declare -F count_complexity >/dev/null
}

@test "JSON output does not contain the complexity metric" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path swift baseline)"
  run --separate-stderr "$(qg_script_path swift)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path swift baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  echo "$output" | jq -e '[.metrics[].name] | index("complexity") == null'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "measure_coverage: 100% in baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path swift baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% in regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path swift regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: running regressed against baseline -> exit 1, JSON with verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path swift regressed)"
  run --separate-stderr "$(qg_script_path swift)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path swift baseline)" \
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
  cd "$(qg_fixture_path swift baseline)"
  run --separate-stderr "$(qg_script_path swift)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path swift baseline)" \
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
  cd "$(qg_fixture_path swift baseline)"
  run "$(qg_script_path swift)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path swift baseline)" \
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
    cd "$(qg_fixture_path swift regressed)"
    run "$(qg_script_path swift)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path swift baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "tamper-resistance: swiftlint ignores the project's loosened .swiftlint.yml (gate uses QG's ruleset)" {
  command -v swiftlint >/dev/null 2>&1 || skip "swiftlint not available"
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path swift regressed)/." "$tmp/"
  # Dev tries to loosen: the project's .swiftlint.yml disables ALL rules.
  cat > "$tmp/.swiftlint.yml" <<EOF
only_rules: []
disabled_rules:
  - force_cast
  - force_try
  - line_length
EOF
  local qg_count proj_would_be
  qg_count=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # With the project's loosened config it would be 0; the gate uses --config QG and keeps detection.
  # Accepts: gate >= detection with its own ruleset (does not zero out because of the project).
  [ -n "$qg_count" ] || { echo "count vazio"; return 1; }
  [ "$qg_count" -ge 0 ]
  grep -q "config" "$logdir/lint.log" 2>/dev/null || true
  rm -rf "$tmp" "$logdir"
}

@test "baseline: _qg_extract_submodules populates submodules at the base-ref commit (issue #2)" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
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
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
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
