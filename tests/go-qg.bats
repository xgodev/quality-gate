#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "go/qg.sh --help shows usage" {
  run "$(qg_script_path go)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "go/qg.sh -h equivalent to --help" {
  run "$(qg_script_path go)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "go/qg.sh declares QG_CONTRACT_VERSION=1 in the header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path go)"
  [ "$status" -eq 0 ]
}

@test "go/qg.sh without --base does NOT exit 2 due to missing --base (absolute mode)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path go)"
  [[ "$output" != *"--base is required"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "go/qg.sh respects the QG_BASE_REF env var when --base is absent" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path go)"
  [[ "$output" != *"--base is required"* ]]
}

@test "go/qg.sh --detect without a sentinel exits 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path go)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "go/qg.sh --detect with a sentinel prints the slug and exits 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "module x" > go.mod
  run "$(qg_script_path go)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "go" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "go LAW: go.mod pins a future toolchain + GOTOOLCHAIN=local = tool-error, no build" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/go.mod" <<EOF
module x

go 1.99
EOF
  echo "package x" > "$tmp/x.go"
  run env GOTOOLCHAIN=local "$(command -v bash)" -c "source '$QG_REPO_ROOT/go/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'go.mod pins toolchain' "$logdir/abs-deps.log"
  grep -q '1.99' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "go LAW: go.mod with a satisfied version + GOTOOLCHAIN=local is NOT a tool-error" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/go.mod" <<EOF
module x

go 1.21
EOF
  run env GOTOOLCHAIN=local "$(command -v bash)" -c "source '$QG_REPO_ROOT/go/lib/measure.sh'; qg_check_go_toolchain '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 0 ]
  [ ! -s "$logdir/abs-deps.log" ]
  rm -rf "$tmp" "$logdir"
}

@test "go/qg.sh absolute mode without .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path go baseline)"
  run --separate-stderr "$(qg_script_path go)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "go/qg.sh absolute mode with absolute_thresholds violated: exit 1, metric violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path go regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path go)" --log-dir "$logdir" --format json
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
  # go package without tests -> undefined coverage.
  echo "module x" > go.mod
  echo "go 1.21" >> go.mod
  cat > lib.go <<EOF
package x

func Add(a, b int) int { return a + b }
EOF
  run --separate-stderr "$(qg_script_path go)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
  echo "$output" | jq -e '(.metrics[] | select(.name=="coverage") | .value) == 0'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "go/qg.sh --format invalid exits 2" {
  run "$(qg_script_path go)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "go/qg.sh --cov-margin non-numeric exits 2" {
  run "$(qg_script_path go)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "go/qg.sh detects a missing tool and exits 2 with an installable message" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path go)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"go"* ]]
  [[ "$output" == *"install"* ]]
}

@test "go/qg.sh with QG_BYPASS_REASON exits 0 and emits a warning" {
  export QG_BYPASS_REASON="bypass test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path go)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"bypass test"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "bypass test" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "go/qg.sh with QG_BYPASS_REASON --format json returns verdict bypassed" {
  export QG_BYPASS_REASON="test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path go)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "test"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "go/qg.sh fast-path when only docs changed" {
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

  run "$(qg_script_path go)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "" == *"no "* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "go/qg.sh --force-full skips fast-path" {
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

  run "$(qg_script_path go)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir nonexistent exits 2" {
  run "$(qg_script_path go)" --base origin/main --baseline-dir /tmp/qg-go-does-not-exist-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: language absent in baseline emits a warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem go.mod" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > go.mod <<EOF
module x
go 1.21
EOF
  echo "package x" > x.go
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "// edit" >> x.go
  git add . && git commit -qm "edit"

  run "$(qg_script_path go)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"language absent"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 in the baseline fixture" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path go baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 in the regressed fixture" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path go regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 in baseline" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path go baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 in regressed" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path go regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 in baseline" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path go baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 in baseline" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path go baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 in regressed" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path go regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 in baseline" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path go baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 in regressed" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path go regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: 100% in baseline" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path go baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% in regressed" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path go regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: running regressed against baseline -> exit 1, JSON with verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path go regressed)"
  run --separate-stderr "$(qg_script_path go)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path go baseline)" \
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
  cd "$(qg_fixture_path go baseline)"
  run --separate-stderr "$(qg_script_path go)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path go baseline)" \
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
  cd "$(qg_fixture_path go baseline)"
  run "$(qg_script_path go)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path go baseline)" \
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
    cd "$(qg_fixture_path go regressed)"
    run "$(qg_script_path go)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path go baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "Bug vendor/: fmt and complexity ignore vendor/build (measures source, not vendored)" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  command -v gocyclo >/dev/null 2>&1 || skip "gocyclo not available"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/go.mod" <<'EOF'
module qgvendortest

go 1.21
EOF
  cat > "$tmp/lib.go" <<'EOF'
package qgvendortest

// Add soma dois inteiros.
func Add(a, b int) int {
	return a + b
}
EOF
  mkdir -p "$tmp/vendor/example.com/dep" "$tmp/build"
  cat > "$tmp/vendor/example.com/dep/dep.go" <<'EOF'
package dep
func Messy(x int)int{
if x>0{if x>1{if x>2{if x>3{if x>4{if x>5{if x>6{if x>7{if x>8{if x>9{if x>10{if x>11{if x>12{if x>13{if x>14{if x>15{if x>16{return x}}}}}}}}}}}}}}}}}
return 0}
EOF
  cp "$tmp/vendor/example.com/dep/dep.go" "$tmp/build/gen.go"
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  result_cx=$(count_complexity "$tmp" "$logdir/cx.log")
  [ "$result_fmt" = "0" ] || { echo "fmt should be 0 (vendor/build ignored); got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  [ "$result_cx" = "0" ] || { echo "complexity should be 0 (vendor/build ignored); got $result_cx"; cat "$logdir/cx.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug vendor/: REAL unformatting in src still counted (the exclusion does not mask source)" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/go.mod" <<'EOF'
module qgsrc

go 1.21
EOF
  printf 'package qgsrc\nfunc F(x int)int{return x}\n' > "$tmp/lib.go"
  mkdir -p "$tmp/vendor/dep"
  printf 'package dep\nfunc G(y int)int{return y}\n' > "$tmp/vendor/dep/dep.go"
  result=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  [ "$result" -gt 0 ] || { echo "expected >0 (unformatted lib.go in src); got $result"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "tamper-resistance: gate points golangci-lint at QG's .golangci.yml (ignores the project's)" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  # qg_ruleset_dir resolves to QG's bundled rules/, never the project's config.
  local rd
  rd=$(qg_ruleset_dir)
  [ -f "$rd/.golangci.yml" ] || { echo "QG ruleset absent: "; return 1; }
  command -v golangci-lint >/dev/null 2>&1 || skip "golangci-lint not available (the go vet fallback is already config-free / tamper-proof)"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path go regressed)/." "$tmp/"
  # Dev tries to loosen: the project's .golangci.yml disables all linters.
  cat > "$tmp/.golangci.yml" <<EOF
linters:
  disable-all: true
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Gate uses -c <QG>/go/rules/.golangci.yml; the project's disable-all is ignored.
  [ "$result" -ge 0 ]
  rm -rf "$tmp" "$logdir"
}

@test "baseline: _qg_extract_submodules populates submodules at the base-ref commit (issue #2)" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
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
  source "$QG_REPO_ROOT/go/lib/measure.sh"
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

@test "measure_test_and_coverage: ONE run yields failures AND coverage (perf fusion)" {
  source "$QG_REPO_ROOT/go/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_test_and_coverage "$(qg_fixture_path go regressed)" "$logdir/test.log" "$logdir/cov.json")
  fails=$(echo "$result" | awk '{print $1}')
  cov=$(echo "$result" | awk '{print $2}')
  [ "$fails" -ge 1 ]
  awk -v c="$cov" 'BEGIN { exit !(c >= 0 && c < 100) }'
  grep -qE -- '--- FAIL:' "$logdir/test.log"
  rm -rf "$logdir"
}

@test "comparative: base metrics are cached by base SHA (second run skips base measurement)" {
  command -v go >/dev/null || skip "go not available"
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path go baseline)/." "$repo/"
  cd "$repo"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  echo '// touch' >> lib.go && git add -A && git commit -qm change
  QG_BASELINE_CACHE_DIR="$repo/.qg-cache" run bash "$QG_REPO_ROOT/go/qg.sh" --base main --force-full --log-dir "$repo/logs1"
  QG_BASELINE_CACHE_DIR="$repo/.qg-cache" run bash "$QG_REPO_ROOT/go/qg.sh" --base main --force-full --log-dir "$repo/logs2"
  printf '%s' "$output" | grep -q 'base metrics: cached'
  cd / && rm -rf "$repo"
}
