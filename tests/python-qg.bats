#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "python/qg.sh --help mostra usage" {
  run "$(qg_script_path python)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "python/qg.sh -h equivalente a --help" {
  run "$(qg_script_path python)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "python/qg.sh declara QG_CONTRACT_VERSION=1 no header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path python)"
  [ "$status" -eq 0 ]
}

@test "python/qg.sh sem --base NAO sai 2 por falta de --base (modo absoluto)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path python)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python/qg.sh respeita QG_BASE_REF env var quando --base ausente" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path python)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
}

@test "python/qg.sh --detect sem sentinela sai 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path python)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python/qg.sh --detect com sentinela imprime slug e sai 0" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  echo "[project]" > pyproject.toml
  run "$(qg_script_path python)" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "python" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python LEI: poetry.lock presente mas poetry fora do PATH = tool-error, sem pip" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/pyproject.toml" <<EOF
[tool.poetry]
name = "x"
version = "0.1.0"
EOF
  echo "# lockfile fake" > "$tmp/poetry.lock"
  # Stub: falha o teste se 'pip' for invocado (substituicao silenciosa).
  local stubdir="$logdir/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/pip" <<EOF
#!/usr/bin/env bash
echo "PIP-FOI-INVOCADO" >> "$logdir/pip-called"
exit 0
EOF
  chmod +x "$stubdir/pip"
  # PATH sem poetry; pip stub presente mas NAO deve ser usado.
  run env PATH="$stubdir:/usr/bin:/bin" "$(command -v bash)" -c "source '$QG_REPO_ROOT/python/lib/measure.sh'; qg_resolve_deps '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'poetry.lock' "$logdir/abs-deps.log"
  grep -q 'poetry' "$logdir/abs-deps.log"
  [ ! -f "$logdir/pip-called" ]
  rm -rf "$tmp" "$logdir"
}

@test "python LEI: uv.lock sem uv = tool-error claro" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "[project]" > "$tmp/pyproject.toml"
  echo "# uv lock" > "$tmp/uv.lock"
  local emptydir="$logdir/emptybin"
  mkdir -p "$emptydir"
  run env PATH="$emptydir" "$(command -v bash)" -c "source '$QG_REPO_ROOT/python/lib/measure.sh'; qg_resolve_lock_manager '$tmp' '$logdir/abs-deps.log'"
  [ "$status" -eq 1 ]
  grep -q '::error::' "$logdir/abs-deps.log"
  grep -q 'uv.lock' "$logdir/abs-deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "python LEI: requirements.txt sem lockfile de manager -> pip legitimo (sem tool-error)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  echo "" > "$tmp/requirements.txt"
  local rc=0
  qg_resolve_lock_manager "$tmp" "$logdir/abs-deps.log" || rc=$?
  [ "$rc" -eq 2 ]
  [ ! -s "$logdir/abs-deps.log" ]
  rm -rf "$tmp" "$logdir"
}

@test "python/qg.sh modo absoluto sem .qg.yaml: exit 0, JSON mode absolute base_ref null" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path python baseline)"
  run --separate-stderr "$(qg_script_path python)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.base_ref == null'
  echo "$output" | jq -e '.schema_version == "1.1"'
  echo "$output" | jq -e '.verdict == "passed"'
  echo "$output" | jq -e '[.metrics[].verdict] | all(. == "reported")'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir"
}

@test "python/qg.sh modo absoluto com absolute_thresholds violado: exit 1, metrica violated" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path python regressed)/." "$tmp/"
  cd "$tmp"
  cat > .qg.yaml <<EOF
absolute_thresholds:
  lint: 0
  test: 0
EOF
  run --separate-stderr "$(qg_script_path python)" --log-dir "$logdir" --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.mode == "absolute"'
  echo "$output" | jq -e '.verdict == "failed"'
  echo "$output" | jq -e '[.metrics[] | select(.verdict == "violated")] | length >= 1'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "Bug 2: coverage indefinida vira 0, JSON valido, gate nao quebra (modo absoluto)" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  # Projeto python sem testes -> coverage indefinida.
  cat > pyproject.toml <<EOF
[project]
name = "x"
version = "0.1.0"
EOF
  cat > mod.py <<EOF
def add(a, b):
    return a + b
EOF
  run --separate-stderr "$(qg_script_path python)" --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
  echo "$output" | jq -e '(.metrics[] | select(.name=="coverage") | .value) == 0'
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "python/qg.sh --format invalido sai 2" {
  run "$(qg_script_path python)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "python/qg.sh --cov-margin nao-numerico sai 2" {
  run "$(qg_script_path python)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "python/qg.sh detecta ferramenta faltando e sai 2 com mensagem instalavel" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path python)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"python"* ]]
  [[ "$output" == *"instale"* ]] || [[ "$output" == *"install"* ]]
}

@test "python/qg.sh com QG_BYPASS_REASON sai 0 e emite warning" {
  export QG_BYPASS_REASON="teste de bypass"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path python)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"teste de bypass"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "teste de bypass" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "python/qg.sh com QG_BYPASS_REASON --format json retorna verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path python)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "teste"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "python/qg.sh fast-path quando so docs mudaram" {
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

  run "$(qg_script_path python)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"nenhum Python"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "python/qg.sh --force-full pula fast-path" {
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

  run "$(qg_script_path python)" --base master --force-full
  [[ "$output" != *"fast-path"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "baseline: --baseline-dir inexistente sai 2" {
  run "$(qg_script_path python)" --base origin/main --baseline-dir /tmp/qg-py-nao-existe-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: linguagem ausente no baseline emite warning + exit 0" {
  local tmp baseline
  tmp=$(qg_tmp_dir)
  baseline=$(qg_tmp_dir)
  echo "# sem pyproject.toml" > "$baseline/README.md"
  cd "$tmp"
  git -c init.defaultBranch=master init -q
  git config user.email "t@t"
  git config user.name "T"
  cat > pyproject.toml <<EOF
[project]
name = "x"
version = "0.1.0"
EOF
  echo "x = 1" > x.py
  git add . && git commit -qm "init"
  git checkout -qb feat
  echo "# edit" >> x.py
  git add . && git commit -qm "edit"

  run "$(qg_script_path python)" --base master --baseline-dir "$baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linguagem ausente"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 no fixture baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path python baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 no fixture regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path python regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 no baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path python baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 no regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path python regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 no baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path python baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 no baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path python baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 no regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path python regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 no baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path python baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 no regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path python regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: 100% no baseline" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path python baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% no regressed" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path python regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: rodando regressed contra baseline -> exit 1, JSON com verdict regressed" {
  local logdir
  logdir=$(qg_tmp_dir)
  cd "$(qg_fixture_path python regressed)"
  run --separate-stderr "$(qg_script_path python)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path python baseline)" \
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
  cd "$(qg_fixture_path python baseline)"
  run --separate-stderr "$(qg_script_path python)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path python baseline)" \
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
  cd "$(qg_fixture_path python baseline)"
  run "$(qg_script_path python)" \
    --base origin/main \
    --baseline-dir "$(qg_fixture_path python baseline)" \
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
    cd "$(qg_fixture_path python regressed)"
    run "$(qg_script_path python)" \
      --base origin/main \
      --baseline-dir "$(qg_fixture_path python baseline)" \
      --log-dir "$logdir" \
      --format json \
      --force-full
    [ "$status" -eq 1 ] || { echo "Iteration $i: status=$status"; return 1; }
    cd "$QG_REPO_ROOT"
    rm -rf "$logdir"
  done
}

@test "Bug build/: lint/complexity/fmt ignoram dirs gerados (mede fonte, nao artefato)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  # src/ real LIMPO: formatado, sem lint/complexity.
  mkdir -p "$tmp/src"
  cat > "$tmp/src/clean.py" <<'EOF'
def add(a, b):
    return a + b
EOF
  # build/ + dist/ GERADO: Python lixo com import nao usado (F401),
  # formatacao ruim e funcao de alta complexidade.
  mkdir -p "$tmp/build/lib" "$tmp/dist"
  cat > "$tmp/build/lib/generated.py" <<'EOF'
import os,sys
def f(x):
 if x>0:
  if x>1:
   if x>2:
    if x>3:
     if x>4:
      if x>5:
       if x>6:
        return undefined_thing
EOF
  cp "$tmp/build/lib/generated.py" "$tmp/dist/bundle.py"
  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_cx=$(count_complexity "$tmp" "$logdir/cx.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  [ "$result_lint" = "0" ] || { echo "lint deveria ser 0 (build/dist ignorados); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_cx" = "0" ] || { echo "complexity deveria ser 0 (build/dist ignorados); got $result_cx"; cat "$logdir/cx.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "fmt deveria ser 0 (so src/ limpo); got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/ tamper: .gitignore vazio do projeto NAO afrouxa -- QG exclui build/ pelo ignore canonico" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  # Dev tenta forcar varredura de tudo: .gitignore VAZIO.
  : > "$tmp/.gitignore"
  mkdir -p "$tmp/src" "$tmp/build"
  cat > "$tmp/src/ok.py" <<'EOF'
def ok():
    return 1
EOF
  cat > "$tmp/build/gen.py" <<'EOF'
import os,sys,json
def bad( ):
    return undefined
EOF
  result_lint=$(count_lint_errors "$tmp" "$logdir/lint.log")
  result_fmt=$(count_fmt_errors "$tmp" "$logdir/fmt.log")
  # extend-exclude do ruff.toml do QG nao depende de respect-gitignore ->
  # build/ excluido mesmo com .gitignore vazio.
  [ "$result_lint" = "0" ] || { echo "tamper: lint deveria ser 0 (extend-exclude do QG); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "tamper: fmt deveria ser 0; got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/: violacao REAL em src/ ainda contada (exclusao nao mascara fonte)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  mkdir -p "$tmp/src" "$tmp/build"
  cat > "$tmp/src/bad.py" <<'EOF'
import os
def f():
    return 1
EOF
  cat > "$tmp/build/gen.py" <<'EOF'
import sys
def g():
    return 2
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  [ "$result" -gt 0 ] || { echo "esperava >0 (F401 real em src/); got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "tamper-resistance: ruff ignora config afrouxada do projeto (gate usa ruleset do QG)" {
  source "$QG_REPO_ROOT/python/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path python regressed)/." "$tmp/"
  # Dev tenta afrouxar: pyproject.toml desliga F401 (import nao usado).
  cat > "$tmp/pyproject.toml" <<EOF
[tool.ruff.lint]
ignore = ["F401", "E", "F", "W", "I"]
[tool.ruff]
line-length = 999
EOF
  cat > "$tmp/ruff.toml" <<EOF
[lint]
ignore = ["F401", "E", "F", "W", "I"]
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Gate ignora config afrouxada (--isolated --config QG) e ainda acusa F401.
  [ "$result" -gt 0 ] || { echo "esperava >0 mesmo com config afrouxada; got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
