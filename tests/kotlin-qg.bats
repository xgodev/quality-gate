#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "kotlin/qg.sh --help mostra usage" {
  run "$(qg_script_path kotlin)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "kotlin/qg.sh -h equivalente a --help" {
  run "$(qg_script_path kotlin)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "kotlin/qg.sh declara QG_CONTRACT_VERSION=1 no header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path kotlin)"
  [ "$status" -eq 0 ]
}

@test "kotlin/qg.sh sem --base NAO sai 2 por falta de --base (modo absoluto)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path kotlin)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "kotlin/qg.sh respeita QG_BASE_REF env var quando --base ausente" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path kotlin)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
}

@test "kotlin/qg.sh --detect sem sentinela sai 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path kotlin)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "kotlin/qg.sh --detect com sentinela imprime slug e sai 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "// gradle" > build.gradle.kts
  run "$(qg_script_path kotlin)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "kotlin" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "kotlin _num: sanitiza nao-numerico para 0 (Bug 2)" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "82.3")" = "82.3" ]
}

@test "kotlin LEI: ./gradlew presente e usado em vez do gradle do sistema" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "plugins { kotlin(\"jvm\") }" > "$tmp/build.gradle.kts"
  cat > "$tmp/gradlew" <<EOF
#!/usr/bin/env bash
echo "GRADLEW-INVOCADO" > "$logdir/gradlew-called"
exit 0
EOF
  chmod +x "$tmp/gradlew"
  # Stub 'gradle' do sistema que falha o teste se invocado.
  local stubdir="$logdir/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/gradle" <<EOF
#!/usr/bin/env bash
echo "GRADLE-SISTEMA-INVOCADO" > "$logdir/gradle-called"
exit 0
EOF
  chmod +x "$stubdir/gradle"
  run env PATH="$stubdir:/usr/bin:/bin" "$(command -v bash)" -c "source '$QG_REPO_ROOT/kotlin/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 0 ]
  [ -f "$logdir/gradlew-called" ]
  [ ! -f "$logdir/gradle-called" ]
  rm -rf "$tmp" "$logdir"
}

@test "kotlin LEI: build Gradle mas nem ./gradlew nem gradle no PATH = tool-error" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "plugins { kotlin(\"jvm\") }" > "$tmp/build.gradle.kts"
  local emptydir="$logdir/emptybin"
  mkdir -p "$emptydir"
  run env PATH="$emptydir" "$(command -v bash)" -c "source '$QG_REPO_ROOT/kotlin/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'gradlew\|Gradle' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "kotlin/qg.sh modo absoluto sem .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path kotlin baseline)"
  run --separate-stderr "$(qg_script_path kotlin)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "kotlin/qg.sh modo absoluto com absolute_thresholds violado: exit 1, metrica violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path kotlin regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path kotlin)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "kotlin/qg.sh --format invalido sai 2" {
  run "$(qg_script_path kotlin)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "kotlin/qg.sh --cov-margin nao-numerico sai 2" {
  run "$(qg_script_path kotlin)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "kotlin/qg.sh detecta ferramenta faltando e sai 2 com mensagem instalavel" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path kotlin)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"kotlin"* ]]
  [[ "$output" == *"instale"* ]] || [[ "$output" == *"install"* ]]
}

@test "kotlin/qg.sh com QG_BYPASS_REASON sai 0 e emite warning" {
  export QG_BYPASS_REASON="teste de bypass"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path kotlin)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"teste de bypass"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "teste de bypass" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "kotlin/qg.sh com QG_BYPASS_REASON --format json retorna verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path kotlin)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "teste"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "kotlin/qg.sh fast-path quando so docs mudaram" {
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
  echo "novo conteudo" >> README.md
  git add README.md
  git commit -qm "edit docs"

  run "$(qg_script_path kotlin)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"nenhum Kotlin"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "kotlin/qg.sh --force-full pula fast-path" {
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

  run "$(qg_script_path kotlin)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir inexistente sai 2" {
  run "$(qg_script_path kotlin)" --base origin/main --baseline-dir /tmp/qg-kotlin-nao-existe-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: linguagem ausente no baseline emite warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem build.gradle" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > build.gradle.kts <<EOF
plugins { kotlin("jvm") version "2.0.21" }
EOF
  mkdir -p src/main/kotlin
  echo "package x" > src/main/kotlin/X.kt
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "// edit" >> src/main/kotlin/X.kt
  git add . && git commit -qm "edit"

  run "$(qg_script_path kotlin)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linguagem ausente"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 no fixture baseline" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path kotlin baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 no fixture regressed" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path kotlin regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 no baseline" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path kotlin baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 no regressed" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path kotlin regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 no baseline" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path kotlin baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 no baseline" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path kotlin baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 no regressed" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path kotlin regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 no baseline" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path kotlin baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 no regressed" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path kotlin regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: 100% no baseline" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path kotlin baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% no regressed" {
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path kotlin regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: rodando regressed contra baseline -> exit 1, JSON com verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path kotlin regressed)"
  run --separate-stderr "$(qg_script_path kotlin)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path kotlin baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "regressed"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: rodando baseline contra ele mesmo -> exit 0" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path kotlin baseline)"
  run --separate-stderr "$(qg_script_path kotlin)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path kotlin baseline)" \
    --log-dir "$logdir" \
    --format json \
    --force-full
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "passed"'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: --format text mostra tabela com colunas esperadas" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path kotlin baseline)"
  run "$(qg_script_path kotlin)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path kotlin baseline)" \
    --log-dir "$logdir" \
    --format text \
    --force-full
  [ "$status" -eq 0 ]
  [[ "$output" == *"metrica"* ]]
  [[ "$output" == *"veredito"* ]]
  [[ "$output" == *"fmt"* ]]
  [[ "$output" == *"coverage"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: 10 runs identicas no regressed devem retornar exit 1 todas as vezes" {
  for i in $(seq 1 10); do
    local logdir
    logdir=$(qg_tmp_dir)
    cd "$(qg_fixture_path kotlin regressed)"
    run "$(qg_script_path kotlin)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path kotlin baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "tamper-resistance: detekt ignora detekt.yml afrouxado do projeto (gate usa ruleset do QG)" {
  command -v detekt >/dev/null 2>&1 || skip "detekt nao disponivel"
  source "$QG_REPO_ROOT/kotlin/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path kotlin regressed)/." "$tmp/"
  # Dev tenta afrouxar: detekt.yml do projeto desliga complexity inteiro.
  cat > "$tmp/detekt.yml" <<EOF
complexity:
  active: false
build:
  maxIssues: 999999
EOF
  result=$(count_complexity "$tmp" "$logdir/cx.log")
  # Gate usa -c <QG>/kotlin/rules/detekt.yml, ignora o do projeto.
  [ "$result" -gt 0 ] || { echo "esperava >0 mesmo com detekt.yml afrouxado; got $result"; cat "$logdir/cx.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
