#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "rust/qg.sh --help mostra usage" {
  run "$(qg_script_path rust)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "rust/qg.sh -h equivalente a --help" {
  run "$(qg_script_path rust)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "rust/qg.sh declara QG_CONTRACT_VERSION=1 no header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path rust)"
  [ "$status" -eq 0 ]
}

@test "rust/qg.sh sem --base NAO sai 2 por falta de --base (modo absoluto)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path rust)"
  [[ "$output" != *"--base é obrigatório"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust/qg.sh respeita QG_BASE_REF env var quando --base ausente" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path rust)"
  # Não deve sair com 2 por falta de --base; pode sair 2 por outras razões adiante.
  [[ "$output" != *"--base é obrigatório"* ]]
}

@test "rust/qg.sh --detect sem sentinela sai 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path rust)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust/qg.sh --detect com sentinela imprime slug e sai 0" {
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

@test "rust LEI: rust-toolchain.toml com channel nao instalado e nao instalavel = tool-error" {
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
  # Stub rustup: channel ausente da lista e 'rustup run' falha (offline).
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

@test "rust LEI: script NAO injeta +stable/override que ignore rust-toolchain.toml" {
  # Ignora linhas de comentario (comecam com # apos espacos): so codigo real.
  run bash -c "grep -vE '^[[:space:]]*#' '$QG_REPO_ROOT/rust/lib/measure.sh' | grep -nE 'cargo[[:space:]]+\+|rustup override set|--toolchain[[:space:]]+stable'"
  [ "$status" -ne 0 ]
}

@test "rust LEI: channel ja instalado NAO e tool-error" {
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

@test "rust/qg.sh modo absoluto sem .qg.yaml: exit 0, JSON mode absolute base_ref null" {
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

@test "rust/qg.sh modo absoluto com absolute_thresholds violado: exit 1, métrica violated" {
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

@test "rust _num: sanitiza não-numérico para 0 (Bug 2)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  [ "$(_num "Unknown")" = "0" ]
  [ "$(_num "")" = "0" ]
  [ "$(_num "82.3")" = "82.3" ]
  [ "$(_num "7")" = "7" ]
}

@test "rust/qg.sh --format inválido sai 2" {
  run "$(qg_script_path rust)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "rust/qg.sh --cov-margin não-numérico sai 2" {
  run "$(qg_script_path rust)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "rust/qg.sh detecta ferramenta faltando e sai 2 com mensagem instalável" {
  # Simula PATH sem cargo
  run env PATH="/usr/bin:/bin" "$(qg_script_path rust)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"cargo"* ]]
  [[ "$output" == *"instale"* ]] || [[ "$output" == *"install"* ]]
}

@test "rust/qg.sh com QG_BYPASS_REASON sai 0 e emite warning" {
  export QG_BYPASS_REASON="teste de bypass"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path rust)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"teste de bypass"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "teste de bypass" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "rust/qg.sh com QG_BYPASS_REASON --format json retorna verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path rust)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "teste"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "rust/qg.sh sem QG_BYPASS_REASON não emite bypass" {
  unset QG_BYPASS_REASON
  run "$(qg_script_path rust)" --base origin/main
  [[ "$output" != *"bypass"* ]]
}

@test "rust/qg.sh fast-path quando só docs mudaram" {
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

  run "$(qg_script_path rust)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"no Rust"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "rust/qg.sh --force-full pula fast-path" {
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

  # --force-full deve continuar e eventualmente sair 2 (sem Cargo.toml) ou tentar medir
  run "$(qg_script_path rust)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test ".qg.yaml inválido (chave desconhecida) sai 2" {
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

@test ".qg.yaml com cov_margin numérico é aceito" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "cov_margin: 3.5" > .qg.yaml
  run "$(qg_script_path rust)" --base origin/main --force-full
  # Pode sair 2 por outras razões (sem git, sem Cargo.toml) mas NÃO por .qg.yaml
  [[ "$output" != *"unknown_key"* ]]
  [[ "$output" != *"chave desconhecida"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test ".qg.yaml skip_metrics sem reason sai 2" {
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

@test "baseline: --baseline-dir inexistente sai 2" {
  run "$(qg_script_path rust)" --base origin/main --baseline-dir /tmp/qg-nao-existe-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "count_fmt: 0 no fixture baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path rust baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 no fixture regressed" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path rust regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 no baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path rust baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 no regressed" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path rust regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 no baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path rust baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 no baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path rust baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 no regressed (test_failing_on_purpose)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path rust regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 no baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path rust baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 no regressed (complex_function)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path rust regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: ~100% no baseline" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path rust baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% no regressed (uncovered exists)" {
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path rust regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: rodando regressed contra baseline → exit 1, JSON com verdict regressed" {
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

@test "e2e: rodando baseline contra ele mesmo → exit 0" {
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

@test "e2e: --format text mostra tabela com colunas esperadas" {
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
  [[ "$output" == *"métrica"* ]]
  [[ "$output" == *"veredito"* ]]
  [[ "$output" == *"fmt"* ]]
  [[ "$output" == *"coverage"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "e2e: 10 runs idênticas no regressed devem retornar exit 1 todas as vezes" {
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

@test "baseline: linguagem ausente no baseline emite warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem Cargo.toml" > "$baseline/README.md"
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
  [[ "$output" == *"linguagem ausente"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "tamper-resistance: clippy ignora clippy.toml afrouxado do projeto (gate usa ruleset do QG)" {
  command -v cargo >/dev/null 2>&1 || skip "cargo nao disponivel"
  source "$QG_REPO_ROOT/rust/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path rust regressed)/." "$tmp/"
  # Dev tenta afrouxar: clippy.toml do projeto eleva thresholds pro infinito.
  cat > "$tmp/clippy.toml" <<EOF
cognitive-complexity-threshold = 99999
too-many-lines-threshold = 99999
too-many-arguments-threshold = 99999
type-complexity-threshold = 999999
EOF
  result=$(count_complexity "$tmp" "$logdir/cx.log")
  # Gate usa CLIPPY_CONF_DIR=<QG>/rust/rules (threshold 25), ignora o do projeto.
  [ "$result" -gt 0 ] || { echo "esperava >0 mesmo com clippy.toml afrouxado; got $result"; cat "$logdir/cx.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
