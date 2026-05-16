#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "java/qg.sh --help mostra usage" {
  run "$(qg_script_path java)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "java/qg.sh -h equivalente a --help" {
  run "$(qg_script_path java)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "java/qg.sh declara QG_CONTRACT_VERSION=1 no header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path java)"
  [ "$status" -eq 0 ]
}

@test "java/qg.sh sem --base NAO sai 2 por falta de --base (modo absoluto)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path java)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "java/qg.sh respeita QG_BASE_REF env var quando --base ausente" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path java)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
}

@test "java/qg.sh --detect sem sentinela sai 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path java)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "java/qg.sh --detect com sentinela imprime slug e sai 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "<project/>" > pom.xml
  run "$(qg_script_path java)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "java" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "java _num: sanitiza nao-numerico para 0 (Bug 2)" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "N/A")" = "0" ]
  [ "$(_num "82.3")" = "82.3" ]
  [ "$(_num "7")" = "7" ]
}

@test "java LEI: projeto Gradle (build.gradle sem pom.xml) = tool-error, sem rodar mvn" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "plugins { id 'java' }" > "$tmp/build.gradle"
  mkdir -p "$tmp/src/main/java"
  echo "package x; class X {}" > "$tmp/src/main/java/X.java"
  # Stub que falha se 'mvn' for invocado (substituicao silenciosa).
  local stubdir="$logdir/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/mvn" <<EOF
#!/usr/bin/env bash
echo "MVN-FOI-INVOCADO" >> "$logdir/mvn-called"
exit 0
EOF
  chmod +x "$stubdir/mvn"
  run env PATH="$stubdir:$PATH" bash -c "source '$QG_REPO_ROOT/java/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'Gradle\|gradle' "$logdir/abs-deps.log"
  grep -q 'apenas Maven' "$logdir/abs-deps.log"
  [ ! -f "$logdir/mvn-called" ]
  rm -rf "$tmp" "$logdir"
}

@test "java LEI: ./mvnw presente e usado em vez do mvn do sistema" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/pom.xml" <<EOF
<?xml version="1.0"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>x</groupId><artifactId>x</artifactId><version>0.1.0</version>
</project>
EOF
  cat > "$tmp/mvnw" <<EOF
#!/usr/bin/env bash
echo "MVNW-INVOCADO" > "$logdir/mvnw-called"
exit 0
EOF
  chmod +x "$tmp/mvnw"
  run env PATH="/usr/bin:/bin" bash -c "source '$QG_REPO_ROOT/java/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 0 ]
  [ -f "$logdir/mvnw-called" ]
  rm -rf "$tmp" "$logdir"
}

@test "java LEI: pom.xml mas nem ./mvnw nem mvn no PATH = tool-error claro" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/pom.xml" <<EOF
<?xml version="1.0"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>x</groupId><artifactId>x</artifactId><version>0.1.0</version>
</project>
EOF
  # PATH so com diretorio vazio: 'mvn' ausente, mas bash ainda resolve
  # (run via bash absoluto). Sem ./mvnw e sem mvn => tool-error.
  local emptydir="$logdir/emptybin"
  mkdir -p "$emptydir"
  run env PATH="$emptydir" "$(command -v bash)" -c "source '$QG_REPO_ROOT/java/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'mvnw\|mvn' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "java/qg.sh modo absoluto sem .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path java baseline)"
  run --separate-stderr "$(qg_script_path java)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "java/qg.sh modo absoluto com absolute_thresholds violado: exit 1, metrica violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path java regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path java)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "java/qg.sh --format invalido sai 2" {
  run "$(qg_script_path java)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "java/qg.sh --cov-margin nao-numerico sai 2" {
  run "$(qg_script_path java)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "java/qg.sh detecta ferramenta faltando e sai 2 com mensagem instalavel" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path java)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"java"* ]]
  [[ "$output" == *"instale"* ]] || [[ "$output" == *"install"* ]]
}

@test "java/qg.sh com QG_BYPASS_REASON sai 0 e emite warning" {
  export QG_BYPASS_REASON="teste de bypass"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path java)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"teste de bypass"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "teste de bypass" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "java/qg.sh com QG_BYPASS_REASON --format json retorna verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path java)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "teste"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "java/qg.sh fast-path quando so docs mudaram" {
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

  run "$(qg_script_path java)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"nenhum Java"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "java/qg.sh --force-full pula fast-path" {
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

  run "$(qg_script_path java)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir inexistente sai 2" {
  run "$(qg_script_path java)" --base origin/main --baseline-dir /tmp/qg-java-nao-existe-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: linguagem ausente no baseline emite warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem pom.xml" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > pom.xml <<EOF
<?xml version="1.0"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>x</groupId>
  <artifactId>x</artifactId>
  <version>0.1.0</version>
</project>
EOF
  mkdir -p src/main/java
  echo "package x; class X {}" > src/main/java/X.java
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "// edit" >> src/main/java/X.java
  git add . && git commit -qm "edit"

  run "$(qg_script_path java)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linguagem ausente"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 no fixture baseline" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path java baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 no fixture regressed" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path java regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 no baseline" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path java baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 no regressed" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path java regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 no baseline" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path java baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 no baseline" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path java baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 no regressed" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path java regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 no baseline" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path java baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 no regressed" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path java regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: > 50% no baseline (jacoco conta default constructor como linha)" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path java baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 50) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < baseline no regressed" {
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path java regressed)" "$logdir/cov.json")
  # baseline ~66.67%, regressed deve estar bem abaixo (uncovered + complexFunction sem teste)
  awk -v r="$result" 'BEGIN { exit !(r < 50) }'
  rm -rf "$logdir"
}

@test "e2e: rodando regressed contra baseline -> exit 1, JSON com verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path java regressed)"
  run --separate-stderr "$(qg_script_path java)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path java baseline)" \
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
  cd "$(qg_fixture_path java baseline)"
  run --separate-stderr "$(qg_script_path java)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path java baseline)" \
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
  cd "$(qg_fixture_path java baseline)"
  run "$(qg_script_path java)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path java baseline)" \
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
    cd "$(qg_fixture_path java regressed)"
    run "$(qg_script_path java)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path java baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "tamper-resistance: pmd ignora ruleset afrouxado do projeto (gate usa ruleset do QG)" {
  command -v pmd >/dev/null 2>&1 || skip "pmd nao disponivel"
  source "$QG_REPO_ROOT/java/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path java regressed)/." "$tmp/"
  # Dev tenta afrouxar: pmd-ruleset.xml vazio no projeto. Gate usa -R <QG>/java/rules/pmd.xml.
  cat > "$tmp/pmd-ruleset.xml" <<EOF
<?xml version="1.0"?>
<ruleset name="afrouxado" xmlns="http://pmd.sourceforge.net/ruleset/2.0.0">
  <description>vazio de proposito</description>
</ruleset>
EOF
  result=$(count_complexity "$tmp" "$logdir/cx.log")
  # Gate usa o ruleset do QG (threshold 10), nao o vazio do projeto.
  [ "$result" -gt 0 ] || { echo "esperava >0 mesmo com ruleset vazio; got $result"; cat "$logdir/cx.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
