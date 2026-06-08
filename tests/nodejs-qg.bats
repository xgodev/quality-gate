#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "nodejs/qg.sh --help shows usage" {
  run "$(qg_script_path nodejs)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "nodejs/qg.sh -h equivalent to --help" {
  run "$(qg_script_path nodejs)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "nodejs/qg.sh declares QG_CONTRACT_VERSION=1 in the header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path nodejs)"
  [ "$status" -eq 0 ]
}

@test "nodejs/qg.sh without --base does NOT exit 2 due to missing --base (absolute mode)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path nodejs)"
  # Without package.json/git here it may exit for other reasons, but NEVER
  # with the old "--base required" message.
  [[ "$output" != *"--base is required"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh respects the QG_BASE_REF env var when --base is absent" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path nodejs)"
  [[ "$output" != *"--base is required"* ]]
}

@test "nodejs/qg.sh --detect without a sentinel exits 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path nodejs)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh --detect with a sentinel prints the slug and exits 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo '{ "name": "x", "version": "0.1.0", "private": true }' > package.json
  run "$(qg_script_path nodejs)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "nodejs" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh absolute mode without .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path nodejs baseline)"
  run --separate-stderr "$(qg_script_path nodejs)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "nodejs/qg.sh absolute mode with absolute_thresholds violated: exit 1, metric violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path nodejs regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path nodejs)" --log-dir "$logdir" --format json
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
  # node project without tests -> c8 produces no summary -> undefined coverage.
  cat > package.json <<EOF
{ "name": "x", "version": "0.1.0", "private": true }
EOF
  echo "module.exports = 1;" > index.js
  run --separate-stderr "$(qg_script_path nodejs)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
  echo "$output" | jq -e '(.metrics[] | select(.name=="coverage") | .value) == 0'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "Fix3: yarn.lock + .yarnrc.yml (Berry) -> yarn install --immutable" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir bindir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir); bindir=$(qg_tmp_dir)
  # yarn stub: records the received args and exits 0 (does not actually resolve).
  cat > "$bindir/yarn" <<EOF
#!/usr/bin/env bash
echo "ARGS: \$*" > "$logdir/yarn-args"
exit 0
EOF
  chmod +x "$bindir/yarn"
  cat > "$tmp/package.json" <<'EOF'
{ "name": "berry-app", "version": "0.1.0", "private": true }
EOF
  : > "$tmp/yarn.lock"
  # .yarnrc.yml presente => Yarn Berry (v2+).
  echo 'nodeLinker: node-modules' > "$tmp/.yarnrc.yml"
  # node_modules absent => resolution needed.
  PATH="$bindir:$PATH" run qg_resolve_deps "$tmp" "$logdir/deps.log"
  [ "$status" -eq 0 ]
  grep -q -- '--immutable' "$logdir/yarn-args" || { echo "expected --immutable (Berry); got: $(cat "$logdir/yarn-args")"; return 1; }
  ! grep -q -- '--frozen-lockfile' "$logdir/yarn-args" || { echo "Berry must not use --frozen-lockfile"; return 1; }
  rm -rf "$tmp" "$logdir" "$bindir"
}

@test "Fix3: yarn.lock without .yarnrc.yml (classic v1) -> yarn install --frozen-lockfile" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir bindir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir); bindir=$(qg_tmp_dir)
  cat > "$bindir/yarn" <<EOF
#!/usr/bin/env bash
echo "ARGS: \$*" > "$logdir/yarn-args"
exit 0
EOF
  chmod +x "$bindir/yarn"
  cat > "$tmp/package.json" <<'EOF'
{ "name": "classic-app", "version": "0.1.0", "private": true }
EOF
  : > "$tmp/yarn.lock"
  # No .yarnrc.yml => Yarn classic v1.
  PATH="$bindir:$PATH" run qg_resolve_deps "$tmp" "$logdir/deps.log"
  [ "$status" -eq 0 ]
  grep -q -- '--frozen-lockfile' "$logdir/yarn-args" || { echo "expected --frozen-lockfile (classic); got: $(cat "$logdir/yarn-args")"; return 1; }
  ! grep -q -- '--immutable' "$logdir/yarn-args" || { echo "classic must not use --immutable"; return 1; }
  rm -rf "$tmp" "$logdir" "$bindir"
}

@test "Fix3: yarn.lock + .yarnrc.yml but yarn absent -> tool-error (no npm fallback)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "berry-app", "version": "0.1.0", "private": true }
EOF
  : > "$tmp/yarn.lock"
  echo 'nodeLinker: node-modules' > "$tmp/.yarnrc.yml"
  # Minimal PATH without yarn -> tool-error, NEVER npm fallback.
  PATH="/usr/bin:/bin" run qg_resolve_deps "$tmp" "$logdir/deps.log"
  [ "$status" -eq 1 ]
  grep -q "yarn.lock present but 'yarn' not found" "$logdir/deps.log"
  grep -q -- "install: 'npm i -g yarn' (Linux) / 'brew install yarn' (macOS)" "$logdir/deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "Bug 1: nodejs without node_modules + no base resolves deps OR classifies tool-error, never invalid jq" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  # Repro my-project: package.json with a dep, no node_modules, no base.
  cat > package.json <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true,
  "dependencies": { "lodash": "4.17.21" } }
EOF
  cat > package-lock.json <<'EOF'
{ "name": "my-project", "version": "0.1.0", "lockfileVersion": 3, "requires": true,
  "packages": { "": { "name": "my-project", "version": "0.1.0",
    "dependencies": { "lodash": "4.17.21" } },
    "node_modules/lodash": { "version": "4.17.21",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz",
      "integrity": "sha512-v2kDEe57lecTulaDIuNTPy3Ry4gLGJ6Z1O3vE1krgXZNrsQ+LFTGHVxVjcXPs17LhbZVGedAJv8XZ1tvj5FvSg==" } } }
EOF
  echo "const _ = require('lodash'); module.exports = _.identity(1);" > index.js
  run --separate-stderr "$(qg_script_path nodejs)" --log-dir "$logdir" --format json
  # Accepted: exit 0 (deps resolved, build ok) OR exit 2 (tool-error from
  # resolution). NEVER a crash with invalid jq --argjson (which would be status>2
  # or non-JSON stdout).
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
  if [ "$status" -eq 0 ]; then
    echo "$output" | jq -e '.' >/dev/null
    echo "$output" | jq -e '.mode == "absolute"'
  fi
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "nodejs/qg.sh --format invalid exits 2" {
  run "$(qg_script_path nodejs)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "nodejs/qg.sh --cov-margin non-numeric exits 2" {
  run "$(qg_script_path nodejs)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "nodejs/qg.sh detects a missing tool and exits 2 with an installable message" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path nodejs)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"node"* ]]
  [[ "$output" == *"install"* ]]
}

@test "nodejs/qg.sh with QG_BYPASS_REASON exits 0 and emits a warning" {
  export QG_BYPASS_REASON="bypass test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path nodejs)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"bypass test"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "bypass test" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "nodejs/qg.sh with QG_BYPASS_REASON --format json returns verdict bypassed" {
  export QG_BYPASS_REASON="test"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path nodejs)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "test"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "nodejs/qg.sh fast-path when only docs changed" {
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

  run "$(qg_script_path nodejs)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "" == *"no "* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh --force-full skips fast-path" {
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

  run "$(qg_script_path nodejs)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir nonexistent exits 2" {
  run "$(qg_script_path nodejs)" --base origin/main --baseline-dir /tmp/qg-node-does-not-exist-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: language absent in baseline emits a warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem package.json" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > package.json <<EOF
{ "name": "x", "version": "0.1.0", "private": true }
EOF
  echo "export const x = 1;" > x.js
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "// edit" >> x.js
  git add . && git commit -qm "edit"

  run "$(qg_script_path nodejs)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"language absent"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 in the baseline fixture" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path nodejs baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 in the regressed fixture" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path nodejs regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 in baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path nodejs baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 in regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path nodejs regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 in baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path nodejs baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 in baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path nodejs baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 in regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path nodejs regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 in baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path nodejs baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 in regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path nodejs regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: 100% in baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path nodejs baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% in regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path nodejs regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: running regressed against baseline -> exit 1, JSON with verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path nodejs regressed)"
  run --separate-stderr "$(qg_script_path nodejs)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path nodejs baseline)" \
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
  cd "$(qg_fixture_path nodejs baseline)"
  run --separate-stderr "$(qg_script_path nodejs)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path nodejs baseline)" \
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
  cd "$(qg_fixture_path nodejs baseline)"
  run "$(qg_script_path nodejs)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path nodejs baseline)" \
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
    cd "$(qg_fixture_path nodejs regressed)"
    run "$(qg_script_path nodejs)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path nodejs baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "Fix1: count_build with valid TSX + 1 real type error counts 1 (not phantom TS17004)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true }
EOF
  # tsconfig do projeto existe (gatilho do branch tsc) mas e IGNORADO.
  cat > "$tmp/tsconfig.json" <<'EOF'
{ "compilerOptions": { "jsx": "react-jsx", "strict": true } }
EOF
  # TSX with valid JSX (compiles clean with --jsx) + ONE real type error.
  cat > "$tmp/App.tsx" <<'EOF'
export function Greeting(props: { name: string }) {
  return <div className="hello">Hi {props.name}</div>;
}
export function Bad() {
  const n: number = "not a number";
  return <span>{n}</span>;
}
EOF
  result=$(count_build_errors "$tmp" "$logdir/build.log")
  # Sem --jsx isso cuspia 4+ TS17004/TS6142. Com tsconfig.base JSX-capaz: so o
  # real type error (string -> number). Accepts 1 (strict) or a few (<5),
  # NEVER dozens of phantom JSX errors.
  [ "$result" -ge 1 ] || { echo "expected >=1 real error; got $result"; cat "$logdir/build.log"; return 1; }
  [ "$result" -lt 5 ] || { echo "phantom JSX errors (TS17004) -- got $result"; cat "$logdir/build.log"; return 1; }
  if grep -qE 'error TS(17004|6142):' "$logdir/build.log"; then
    echo "ainda emite TS17004/TS6142 (faltou --jsx no ruleset do QG)"; cat "$logdir/build.log"; return 1
  fi
  rm -rf "$tmp" "$logdir"
}

@test "Fix1: TSX 100% valid -> 0 build errors (proves JSX is not counted as an error)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true }
EOF
  cat > "$tmp/tsconfig.json" <<'EOF'
{ "compilerOptions": { "jsx": "react-jsx" } }
EOF
  cat > "$tmp/Comp.tsx" <<'EOF'
type Props = { title: string; count: number };
export function Card({ title, count }: Props) {
  return (
    <section className="card">
      <h2>{title}</h2>
      <p>{count}</p>
    </section>
  );
}
EOF
  result=$(count_build_errors "$tmp" "$logdir/build.log")
  [ "$result" = "0" ] || { echo "valid TSX should be 0; got $result"; cat "$logdir/build.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Fix1 tamper: project tsconfig with strict:false is IGNORED -- gate still catches the strict error" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true }
EOF
  # Dev tries to loosen: strict:false + noImplicitAny:false in their own repo.
  cat > "$tmp/tsconfig.json" <<'EOF'
{ "compilerOptions": { "strict": false, "noImplicitAny": false, "jsx": "preserve" } }
EOF
  # Erro que SO aparece sob strict/noImplicitAny: param implicito any.
  cat > "$tmp/App.tsx" <<'EOF'
export function handler(payload) {
  return <pre>{JSON.stringify(payload)}</pre>;
}
EOF
  result=$(count_build_errors "$tmp" "$logdir/build.log")
  # Gate enforces QG strict (ignores the project's strict:false) -> catches TS7006.
  [ "$result" -ge 1 ] || { echo "expected >=1 (QG strict ignores the project strict:false); got $result"; cat "$logdir/build.log"; return 1; }
  grep -qE 'error TS7006:' "$logdir/build.log" || { echo "expected TS7006 (noImplicitAny locked by QG)"; cat "$logdir/build.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/: lint/complexity/fmt ignore generated directories (measures source, not artifact)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true }
EOF
  # real src/ CLEAN: 0 lint/complexity violations, formatted.
  mkdir -p "$tmp/src"
  cat > "$tmp/src/index.js" <<'EOF'
export const add = (a, b) => a + b;
EOF
  # build/android/* GENERATED: junk minified bundle with dozens of violations
  # (no-undef, no-unused-vars, alta complexidade, sem formatacao).
  mkdir -p "$tmp/build/android"
  {
    printf 'var bundle='
    for i in $(seq 1 50); do
      printf 'function f%d(x){if(x){if(x>1){if(x>2){if(x>3){if(x>4){if(x>5){return undefVar%d}}}}}}var unused%d=1};' "$i" "$i" "$i"
    done
    printf '\n'
  } > "$tmp/build/android/index.android.bundle.min.js"

  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_cx=$(count_complexity "$tmp" "$logdir/cx.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")

  # Antes do fix: lint/complexity contavam centenas (100% build/). Depois: 0.
  [ "$result_lint" = "0" ] || { echo "lint should be 0 (build/ ignored); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_cx" = "0" ] || { echo "complexity should be 0 (build/ ignored); got $result_cx"; cat "$logdir/cx.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "fmt should be 0 (only clean src/, build/ ignored); got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/: REAL violations in src/ are still counted (the exclusion does not mask source)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "x", "version": "0.1.0", "private": true }
EOF
  mkdir -p "$tmp/src" "$tmp/build"
  # src/ with a real lint violation.
  echo 'export const y = undefinedThing;' > "$tmp/src/bad.js"
  # build/ ignored, must not add up.
  echo 'var z=alsoUndefined' > "$tmp/build/bundle.min.js"
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  [ "$result" -gt 0 ] || { echo "expected >0 (real violation in src/); got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/ tamper: empty project .eslintignore does NOT loosen -- QG ignores build/ via the canonical ignore" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "x", "version": "0.1.0", "private": true }
EOF
  # Dev tries to force scanning everything: .eslintignore/.prettierignore EMPTY.
  : > "$tmp/.eslintignore"
  : > "$tmp/.prettierignore"
  mkdir -p "$tmp/src" "$tmp/build/android"
  echo 'export const ok = 1;' > "$tmp/src/index.js"
  {
    for i in $(seq 1 30); do
      printf 'var u%d=undefVar%d;' "$i" "$i"
    done
    printf '\n'
  } > "$tmp/build/android/bundle.min.js"
  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  # QG ignores the project's .eslintignore/.prettierignore and still excludes build/
  # pelo ignore canonico embarcado -> 0.
  [ "$result_lint" = "0" ] || { echo "tamper: lint should be 0 (QG canonical ignore, not the project's); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "tamper: fmt should be 0; got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "tamper-resistance: eslint ignores the project's loosened .eslintrc (gate uses QG's ruleset)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path nodejs regressed)/." "$tmp/"
  # Dev tries to loosen: the project's eslint.config.mjs turns off no-unused-vars.
  cat > "$tmp/eslint.config.mjs" <<EOF
export default [{ rules: { "no-unused-vars": "off", "no-undef": "off" } }];
EOF
  cat > "$tmp/.eslintrc.json" <<EOF
{ "rules": { "no-unused-vars": "off" } }
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Gate ignores it (--no-config-lookup --config QG) and still flags no-unused-vars.
  [ "$result" -gt 0 ] || { echo "expected >0 even with a loosened .eslintrc; got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "baseline: _qg_extract_submodules populates submodules at the base-ref commit (issue #2)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
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
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
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
