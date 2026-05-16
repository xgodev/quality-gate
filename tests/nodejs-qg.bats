#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  qg_clean_env
}

@test "nodejs/qg.sh --help mostra usage" {
  run "$(qg_script_path nodejs)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "nodejs/qg.sh -h equivalente a --help" {
  run "$(qg_script_path nodejs)" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--base"* ]]
}

@test "nodejs/qg.sh declara QG_CONTRACT_VERSION=1 no header" {
  run grep -E "^# QG_CONTRACT_VERSION=1$" "$(qg_script_path nodejs)"
  [ "$status" -eq 0 ]
}

@test "nodejs/qg.sh sem --base NAO sai 2 por falta de --base (modo absoluto)" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path nodejs)"
  # Sem package.json/git aqui pode sair por outros motivos, mas NUNCA
  # com a mensagem antiga de "--base obrigatorio".
  [[ "$output" != *"--base eh obrigatorio"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh respeita QG_BASE_REF env var quando --base ausente" {
  export QG_BASE_REF="origin/main"
  run "$(qg_script_path nodejs)"
  [[ "$output" != *"--base eh obrigatorio"* ]]
}

@test "nodejs/qg.sh --detect sem sentinela sai 1" {
  local tmp
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  run "$(qg_script_path nodejs)" --detect
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh --detect com sentinela imprime slug e sai 0" {
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

@test "nodejs/qg.sh modo absoluto sem .qg.yaml: exit 0, JSON mode absolute base_ref null" {
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

@test "nodejs/qg.sh modo absoluto com absolute_thresholds violado: exit 1, metrica violated" {
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

@test "Bug 2: coverage indefinida vira 0, JSON valido, gate nao quebra (modo absoluto)" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  # Projeto node sem testes -> c8 nao gera summary -> coverage indefinida.
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
  # Stub de yarn: grava os args recebidos e sai 0 (nao resolve de verdade).
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
  # node_modules ausente => resolucao necessaria.
  PATH="$bindir:$PATH" run qg_resolve_deps "$tmp" "$logdir/deps.log"
  [ "$status" -eq 0 ]
  grep -q -- '--immutable' "$logdir/yarn-args" || { echo "esperava --immutable (Berry); got: $(cat "$logdir/yarn-args")"; return 1; }
  ! grep -q -- '--frozen-lockfile' "$logdir/yarn-args" || { echo "Berry nao deve usar --frozen-lockfile"; return 1; }
  rm -rf "$tmp" "$logdir" "$bindir"
}

@test "Fix3: yarn.lock sem .yarnrc.yml (classic v1) -> yarn install --frozen-lockfile" {
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
  # Sem .yarnrc.yml => Yarn classic v1.
  PATH="$bindir:$PATH" run qg_resolve_deps "$tmp" "$logdir/deps.log"
  [ "$status" -eq 0 ]
  grep -q -- '--frozen-lockfile' "$logdir/yarn-args" || { echo "esperava --frozen-lockfile (classic); got: $(cat "$logdir/yarn-args")"; return 1; }
  ! grep -q -- '--immutable' "$logdir/yarn-args" || { echo "classic nao deve usar --immutable"; return 1; }
  rm -rf "$tmp" "$logdir" "$bindir"
}

@test "Fix3: yarn.lock + .yarnrc.yml mas yarn ausente -> tool-error (nao fallback npm)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "berry-app", "version": "0.1.0", "private": true }
EOF
  : > "$tmp/yarn.lock"
  echo 'nodeLinker: node-modules' > "$tmp/.yarnrc.yml"
  # PATH minimo sem yarn -> tool-error, NUNCA fallback npm.
  PATH="/usr/bin:/bin" run qg_resolve_deps "$tmp" "$logdir/deps.log"
  [ "$status" -eq 1 ]
  grep -q "yarn.lock presente mas 'yarn' nao encontrado" "$logdir/deps.log"
  grep -q -- "instale: 'npm i -g yarn' (Linux) / 'brew install yarn' (macOS)" "$logdir/deps.log"
  rm -rf "$tmp" "$logdir"
}

@test "Bug 1: nodejs sem node_modules + sem base resolve deps OU classifica tool-error, nunca jq invalido" {
  local logdir tmp
  logdir=$(qg_tmp_dir)
  tmp=$(qg_tmp_dir)
  cd "$tmp"
  # Repro my-project: package.json com dep, sem node_modules, sem base.
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
  # Aceito: exit 0 (deps resolvidas, build ok) OU exit 2 (tool-error de
  # resolucao). NUNCA crash com jq --argjson invalido (que seria status>2
  # ou stdout nao-JSON).
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
  if [ "$status" -eq 0 ]; then
    echo "$output" | jq -e '.' >/dev/null
    echo "$output" | jq -e '.mode == "absolute"'
  fi
  cd "$QG_REPO_ROOT"
  rm -rf "$logdir" "$tmp"
}

@test "nodejs/qg.sh --format invalido sai 2" {
  run "$(qg_script_path nodejs)" --base origin/main --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"--format"* ]]
}

@test "nodejs/qg.sh --cov-margin nao-numerico sai 2" {
  run "$(qg_script_path nodejs)" --base origin/main --cov-margin abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cov-margin"* ]]
}

@test "nodejs/qg.sh detecta ferramenta faltando e sai 2 com mensagem instalavel" {
  run env PATH="/usr/bin:/bin" "$(qg_script_path nodejs)" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *"node"* ]]
  [[ "$output" == *"instale"* ]] || [[ "$output" == *"install"* ]]
}

@test "nodejs/qg.sh com QG_BYPASS_REASON sai 0 e emite warning" {
  export QG_BYPASS_REASON="teste de bypass"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path nodejs)" --base origin/main --log-dir "$logdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"bypass"* ]]
  [[ "$output" == *"teste de bypass"* ]]
  [ -f "$logdir/bypass.log" ]
  grep -q "teste de bypass" "$logdir/bypass.log"
  rm -rf "$logdir"
}

@test "nodejs/qg.sh com QG_BYPASS_REASON --format json retorna verdict bypassed" {
  export QG_BYPASS_REASON="teste"
  local logdir
  logdir=$(qg_tmp_dir)
  run "$(qg_script_path nodejs)" --base origin/main --log-dir "$logdir" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "bypassed"'
  echo "$output" | jq -e '.bypass_reason == "teste"'
  echo "$output" | jq -e '.metrics | length == 0'
  rm -rf "$logdir"
}

@test "nodejs/qg.sh fast-path quando so docs mudaram" {
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

  run "$(qg_script_path nodejs)" --base master
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-path"* ]] || [[ "$output" == *"nenhum Node.js"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp"
}

@test "nodejs/qg.sh --force-full pula fast-path" {
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

@test "baseline: --baseline-dir inexistente sai 2" {
  run "$(qg_script_path nodejs)" --base origin/main --baseline-dir /tmp/qg-node-nao-existe-xyz --force-full
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline"* ]] || [[ "$output" == *"--baseline-dir"* ]]
}

@test "baseline: linguagem ausente no baseline emite warning + exit 0" {
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
  [[ "$output" == *"linguagem ausente"* ]] || [[ "$output" == *"skipped"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$tmp" "$baseline"
}

@test "count_fmt: 0 no fixture baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path nodejs baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_fmt: > 0 no fixture regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_fmt_errors "$(qg_fixture_path nodejs regressed)" "$logdir/test.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_lint: 0 no baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path nodejs baseline)" "$logdir/lint.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_lint: > 0 no regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_lint_errors "$(qg_fixture_path nodejs regressed)" "$logdir/lint.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "count_build: 0 no baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_build_errors "$(qg_fixture_path nodejs baseline)" "$logdir/build.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 0 no baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path nodejs baseline)" "$logdir/test.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_test: 1 no regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_test_failures "$(qg_fixture_path nodejs regressed)" "$logdir/test.log")
  [ "$result" = "1" ]
  rm -rf "$logdir"
}

@test "count_complexity: 0 no baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path nodejs baseline)" "$logdir/cx.log")
  [ "$result" = "0" ]
  rm -rf "$logdir"
}

@test "count_complexity: > 0 no regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(count_complexity "$(qg_fixture_path nodejs regressed)" "$logdir/cx.log")
  [ "$result" -gt 0 ]
  rm -rf "$logdir"
}

@test "measure_coverage: 100% no baseline" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path nodejs baseline)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r >= 90) }'
  rm -rf "$logdir"
}

@test "measure_coverage: < 100% no regressed" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local logdir
  logdir=$(qg_tmp_dir)
  result=$(measure_coverage "$(qg_fixture_path nodejs regressed)" "$logdir/cov.json")
  awk -v r="$result" 'BEGIN { exit !(r < 100) }'
  rm -rf "$logdir"
}

@test "e2e: rodando regressed contra baseline -> exit 1, JSON com verdict regressed" {
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

@test "e2e: rodando baseline contra ele mesmo -> exit 0" {
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

@test "e2e: --format text mostra tabela com colunas esperadas" {
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

@test "Fix1: count_build com TSX valido + 1 erro de tipo real conta 1 (nao TS17004 fantasma)" {
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
  # TSX com JSX valido (compila limpo com --jsx) + UM erro de tipo real.
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
  # erro de tipo real (string -> number). Aceita 1 (estrito) ou poucos (<5),
  # NUNCA dezenas de erros fantasma de JSX.
  [ "$result" -ge 1 ] || { echo "esperava >=1 erro real; got $result"; cat "$logdir/build.log"; return 1; }
  [ "$result" -lt 5 ] || { echo "erros fantasma de JSX (TS17004) -- got $result"; cat "$logdir/build.log"; return 1; }
  if grep -qE 'error TS(17004|6142):' "$logdir/build.log"; then
    echo "ainda emite TS17004/TS6142 (faltou --jsx no ruleset do QG)"; cat "$logdir/build.log"; return 1
  fi
  rm -rf "$tmp" "$logdir"
}

@test "Fix1: TSX 100% valido -> 0 build errors (prova que JSX nao e contado como erro)" {
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
  [ "$result" = "0" ] || { echo "TSX valido deveria dar 0; got $result"; cat "$logdir/build.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Fix1 tamper: tsconfig do projeto com strict:false e IGNORADO -- gate ainda pega erro strict" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true }
EOF
  # Dev tenta afrouxar: strict:false + noImplicitAny:false no proprio repo.
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
  # Gate impoe strict do QG (ignora strict:false do projeto) -> pega TS7006.
  [ "$result" -ge 1 ] || { echo "esperava >=1 (strict do QG ignora strict:false do projeto); got $result"; cat "$logdir/build.log"; return 1; }
  grep -qE 'error TS7006:' "$logdir/build.log" || { echo "esperava TS7006 (noImplicitAny travado pelo QG)"; cat "$logdir/build.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/: lint/complexity/fmt ignoram diretorios gerados (mede fonte, nao artefato)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "my-project", "version": "0.1.0", "private": true }
EOF
  # src/ real LIMPO: 0 violacoes de lint/complexity, formatado.
  mkdir -p "$tmp/src"
  cat > "$tmp/src/index.js" <<'EOF'
export const add = (a, b) => a + b;
EOF
  # build/android/* GERADO: bundle minificado lixo com dezenas de violacoes
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
  [ "$result_lint" = "0" ] || { echo "lint deveria ser 0 (build/ ignorado); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_cx" = "0" ] || { echo "complexity deveria ser 0 (build/ ignorado); got $result_cx"; cat "$logdir/cx.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "fmt deveria ser 0 (so src/ limpo, build/ ignorado); got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/: violacoes REAIS em src/ ainda sao contadas (exclusao nao mascara fonte)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "x", "version": "0.1.0", "private": true }
EOF
  mkdir -p "$tmp/src" "$tmp/build"
  # src/ com violacao real de lint.
  echo 'export const y = undefinedThing;' > "$tmp/src/bad.js"
  # build/ ignorado, nao deve somar.
  echo 'var z=alsoUndefined' > "$tmp/build/bundle.min.js"
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  [ "$result" -gt 0 ] || { echo "esperava >0 (violacao real em src/); got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "Bug build/ tamper: .eslintignore vazio do projeto NAO afrouxa -- QG ignora build/ pelo ignore canonico" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cat > "$tmp/package.json" <<'EOF'
{ "name": "x", "version": "0.1.0", "private": true }
EOF
  # Dev tenta forcar varredura de tudo: .eslintignore/.prettierignore VAZIOS.
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
  # QG ignora o .eslintignore/.prettierignore do projeto e ainda exclui build/
  # pelo ignore canonico embarcado -> 0.
  [ "$result_lint" = "0" ] || { echo "tamper: lint deveria ser 0 (ignore canonico do QG, nao do projeto); got $result_lint"; cat "$logdir/lint.log"; return 1; }
  [ "$result_fmt" = "0" ] || { echo "tamper: fmt deveria ser 0; got $result_fmt"; cat "$logdir/fmt.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}

@test "tamper-resistance: eslint ignora .eslintrc afrouxado do projeto (gate usa ruleset do QG)" {
  source "$QG_REPO_ROOT/nodejs/lib/measure.sh"
  local tmp logdir
  tmp=$(qg_tmp_dir); logdir=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path nodejs regressed)/." "$tmp/"
  # Dev tenta afrouxar: eslint.config.mjs do projeto desliga no-unused-vars.
  cat > "$tmp/eslint.config.mjs" <<EOF
export default [{ rules: { "no-unused-vars": "off", "no-undef": "off" } }];
EOF
  cat > "$tmp/.eslintrc.json" <<EOF
{ "rules": { "no-unused-vars": "off" } }
EOF
  result=$(count_lint_errors "$tmp" "$logdir/lint.log")
  # Gate ignora (--no-config-lookup --config QG) e ainda acusa no-unused-vars.
  [ "$result" -gt 0 ] || { echo "esperava >0 mesmo com .eslintrc afrouxado; got $result"; cat "$logdir/lint.log"; return 1; }
  rm -rf "$tmp" "$logdir"
}
