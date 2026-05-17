#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "web/qg.sh --help shows usage" {
  run "$(qg_script_path web)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"OMITIDAS"* ]] || [[ "$output" == *"fmt"* ]]
}

@test "web/qg.sh declares QG_CONTRACT_VERSION=1 in the header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path web)"
  [ "$status" -eq 0 ]
}

@test "web/qg.sh --detect without HTML/CSS exits 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path web)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "web/qg.sh --detect with HTML at the root and NO package.json prints slug + exits 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "<!doctype html><title>x</title>" > index.html
  run "$(qg_script_path web)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "web" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "web/qg.sh --detect with package.json (nodejs project) does NOT detect web" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "<!doctype html><title>x</title>" > index.html
  echo '{"name":"x"}' > package.json
  run "$(qg_script_path web)" --detect
  [ "$status" -eq 1 ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "web/qg.sh --format invalid exits 2" {
  run "$(qg_script_path web)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "web/qg.sh with QG_BYPASS_REASON --format json returns verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path web)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "web count_fmt: 0 in baseline" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path web baseline)" "$logdir/fmt.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "web count_fmt: > 0 in regressed" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path web regressed)" "$logdir/fmt.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "web count_lint: 0 in baseline" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path web baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "web count_lint: > 0 in regressed (stylelint + htmlhint)" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path web regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "web _num: sanitizes non-numeric to 0 (Bug 2)" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "3")" = "3" ]
}

@test "web/qg.sh absolute mode without .qg.yaml: exit 0, JSON mode absolute, only fmt+lint" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path web baseline)"
  run --separate-stderr "$(qg_script_path web)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.language == "web"'
  echo "$output" | jq -e '[.metrics[].name] | sort == ["fmt","lint"]'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "web/qg.sh absolute mode with absolute_thresholds violated: exit 1, metric violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path web regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  fmt: 0
EOF
  run --separate-stderr "$(qg_script_path web)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "web/qg.sh .qg.yaml absolute_thresholds with an omitted-metric key (build) exits 2" {
  local tmp
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path web baseline)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  build: 0
EOF
  run "$(qg_script_path web)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"absolute_thresholds"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "web/qg.sh e2e: regressed contra baseline -> exit 1, verdict regressed (so fmt+lint)" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path web regressed)"
  run --separate-stderr "$(qg_script_path web)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path web baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "regressed"'
  echo "$output" | jq -e '[.metrics[].name] | sort == ["fmt","lint"]'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "web/qg.sh e2e: baseline contra ele mesmo -> exit 0 passed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path web baseline)"
  run --separate-stderr "$(qg_script_path web)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path web baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "passed"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "web Bug build/: fmt/lint ignore generated dirs (measures source, not artifact)" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  # src/ real LIMPO (CSS + HTML formatados pelo padrao do QG).
  mkdir -p "$tmp/src"
  cat > "$tmp/src/style.css" <<'EOF'
.a {
  color: #fff;
}
EOF
  cat > "$tmp/src/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>ok</title>
  </head>
  <body>
    <main><p>ok</p></main>
  </body>
</html>
EOF
  # build/ + dist/ GENERATED: junk CSS/HTML, unformatted, with violations.
  mkdir -p "$tmp/build" "$tmp/dist"
  printf '.x{color:red;;}  .y{}\n' > "$tmp/build/bundle.min.css"
  printf '<html><body><img src=a></body>\n' > "$tmp/build/index.html"
  printf '.z{COLOR:#ABC}\n' > "$tmp/dist/app.css"
  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  [ "$result_lint" = "0" ] || { echo "lint should be 0 (build/dist ignored); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "fmt should be 0 (only clean src/); got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "web Bug build/: REAL violations in src/ still counted (the exclusion does not mask source)" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  mkdir -p "$tmp/src" "$tmp/build"
  # Violacao real do ruleset do QG: hex invalido (color-no-invalid-hex).
  printf '.bad {\n  color: #zzzzzz;\n}\n' > "$tmp/src/style.css"
  printf '.gen {\n  color: #yyyyyy;\n}\n' > "$tmp/build/bundle.min.css"
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  [ "$result" -gt 0 ] || { echo "expected >0 (real violation in src/); got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "web/qg.sh tamper-resistance: ignores the project's loosened .stylelintrc" {
  source "$QG_REPO_ROOT/web/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path web regressed)/." "$tmp/"
  # Dev tries to loosen: the project's .stylelintrc.json with no rules.
  cat > "$tmp/.stylelintrc.json" <<EOF
{ "rules": {} }
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Gate usa --config <QG>/web/rules/.stylelintrc.json, ignora o do projeto.
  [ "$result" -gt 0 ] || { echo "expected >0 even with an empty .stylelintrc; got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
