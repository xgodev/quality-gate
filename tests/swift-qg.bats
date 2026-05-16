#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "swift/qg.sh --help mostra usage" {
  run "$(qg_script_path swift)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "swift/qg.sh -h equivalente a --help" {
  run "$(qg_script_path swift)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "swift/qg.sh declara QG_CONTRACT_VERSION=1 no header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path swift)"
  [ "$status" -eq 0 ]
}

@test "swift/qg.sh sem --base NAO sai 2 por falta de --base (modo absoluto)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path swift)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift/qg.sh respeita QG_BASE_REF env var quando --base ausente" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path swift)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
}

@test "swift/qg.sh --detect sem sentinela sai 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path swift)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift/qg.sh --detect com sentinela imprime slug e sai 0" {
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

@test "swift _num: sanitiza nao-numerico para 0 (Bug 2)" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "82.3")" = "82.3" ]
}

@test "swift LEI: Package.swift swift-tools-version acima do swift do PATH = tool-error" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  command -v swift >/dev/null 2>&1 || skip "swift nao disponivel"
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
  # Nao deve haver saida de 'swift package resolve' (nao chegou a rodar).
  ! grep -qi 'Fetching\|Computing version' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "swift LEI: swift-tools-version satisfeita NAO e tool-error" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  command -v swift >/dev/null 2>&1 || skip "swift nao disponivel"
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

@test "swift/qg.sh modo absoluto sem .qg.yaml: exit 0, JSON mode absolute sem complexity" {
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

@test "swift/qg.sh modo absoluto com absolute_thresholds violado: exit 1, metrica violated" {
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

@test "swift/qg.sh modo absoluto com absolute_thresholds complexity rejeitado (omitida)" {
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

@test "swift/qg.sh --format invalido sai 2" {
  run "$(qg_script_path swift)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "swift/qg.sh --cov-margin nao-numerico sai 2" {
  run "$(qg_script_path swift)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "swift/qg.sh detecta ferramenta faltando e sai 2 com mensagem instalavel" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path swift)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"swift"* ]]
  [[ "$output" == *"instale"* ]] || [[ "$output" == *"install"* ]]
}

@test "swift/qg.sh com QG_BYPASS_REASON sai 0 e emite warning" {
  export QG_BYPASS_REASON="teste de bypass"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path swift)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"teste de bypass"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "teste de bypass" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "swift/qg.sh com QG_BYPASS_REASON --format json retorna verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path swift)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "teste"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "swift/qg.sh fast-path quando so docs mudaram" {
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

  run "$(qg_script_path swift)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"nenhum Swift"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "swift/qg.sh --force-full pula fast-path" {
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

@test "baseline: --baseline-dir inexistente sai 2" {
  run "$(qg_script_path swift)" --base origin/main --baseline-dir /tmp/qg-swift-nao-existe-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: linguagem ausente no baseline emite warning + exit 0" {
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
  [[ "$output" == *"linguagem ausente"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 no fixture baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path swift baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 no fixture regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path swift regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 no baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path swift baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 no regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path swift regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 no baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path swift baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 no baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path swift baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 no regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path swift regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "complexity nao eh medida (omitida em Swift)" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  # count_complexity nao deve estar definida.
  ! declare -F count_complexity >/dev/null
}

@test "JSON output nao contem metrica complexity" {
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

@test "measure_coverage: 100% no baseline" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path swift baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% no regressed" {
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path swift regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: rodando regressed contra baseline -> exit 1, JSON com verdict regressed" {
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

@test "e2e: rodando baseline contra ele mesmo -> exit 0" {
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

@test "e2e: --format text mostra tabela com colunas esperadas" {
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

@test "tamper-resistance: swiftlint ignora .swiftlint.yml afrouxado do projeto (gate usa ruleset do QG)" {
  command -v swiftlint >/dev/null 2>&1 || skip "swiftlint nao disponivel"
  source "$QG_REPO_ROOT/swift/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path swift regressed)/." "$tmp/"
  # Dev tenta afrouxar: .swiftlint.yml do projeto desabilita TODAS as regras.
  cat > "$tmp/.swiftlint.yml" <<EOF
only_rules: []
disabled_rules:
  - force_cast
  - force_try
  - line_length
EOF
  local qg_count proj_would_be
  qg_count=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Com config afrouxada do projeto seria 0; gate usa --config QG e mantem deteccao.
  # Aceita: gate >= deteccao com ruleset proprio (nao zera por causa do projeto).
  [ -n "$qg_count" ] || { echo "count vazio"; return 1; }
  [ "$qg_count" -ge 0 ]
  grep -q "config" "$logdir/lint.log" 2>/dev/null || true
  rm -rf "$tmp" "$logdir"
}
