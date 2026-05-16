#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

# Cria um ROOT falso com gates sinteticos controlaveis. Cada fake gate:
#  --detect : exit 0 + imprime slug se existe <sentinela> no cwd, senao exit 1
#  (sem --detect): imprime JSON minimo e sai com o codigo gravado em
#                  $FAKE_<SLUG>_EXIT (default 0); ecoa os args recebidos.
make_fake_root() {
  local root="$1"; shift
  mkdir -p "$root"
  cp "$QG_REPO_ROOT/qg" "$root/qg"
  chmod +x "$root/qg"
  while [ $# -gt 0 ]; do
    local slug="$1" sentinel="$2" exitcode="$3"
    shift 3
    mkdir -p "$root/$slug"
    cat > "$root/$slug/qg.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
SLUG="$slug"
SENT="$sentinel"
RC=$exitcode
for a in "\$@"; do
  if [ "\$a" = "--detect" ]; then
    if [ -f "./\$SENT" ]; then echo "\$SLUG"; exit 0; fi
    exit 1
  fi
done
echo "{\"schema_version\":\"1.1\",\"mode\":\"comparative\",\"language\":\"\$SLUG\",\"branch\":\"x\",\"base_ref\":\"origin/main\",\"started_at\":\"2026-05-15T10:00:00Z\",\"duration_seconds\":1,\"verdict\":\"passed\",\"bypass_reason\":null,\"metrics\":[]}"
exit \$RC
EOF
    chmod +x "$root/$slug/qg.sh"
  done
}

setup() {
  qg_clean_env
}

@test "dispatcher: 0 matches -> exit 3 + mensagem" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 0
  cd "$proj"
  run "$root/qg" --base origin/main
  [ "$status" -eq 3 ]
  [[ "$output" == *"nenhuma linguagem suportada detectada"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: 1 match -> repassa exit code do gate" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 1 nodejs NODE_SENTINEL 0
  cd "$proj"
  touch GO_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 1 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: 1 match exit 0 -> exit 0" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  cd "$proj"; touch GO_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 0 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches -> roda todos, veredito agregado = pior (1 vence 0)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 1
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 1 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches -> precedencia 2 > 1 (tool error vence regressao)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 1 nodejs NODE_SENTINEL 2
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 2 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches --format json -> array envelopado com aggregate_verdict" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 1
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --base origin/main --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.aggregate_verdict == "regressed"'
  echo "$output" | jq -e '.results | length == 2'
  echo "$output" | jq -e '.schema_version == "1.1"'
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: --detect lista slugs detectados, exit 0" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 0
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --detect
  [ "$status" -eq 0 ]
  [[ "$output" == *"go"* ]]
  [[ "$output" == *"nodejs"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: --detect sem matches -> exit 3" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  cd "$proj"
  run "$root/qg" --detect
  [ "$status" -eq 3 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: .qg.yaml projects: usa APENAS a lista (monorepo)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 1
  mkdir -p "$proj/backend" "$proj/frontend"
  touch "$proj/backend/GO_SENTINEL" "$proj/frontend/NODE_SENTINEL"
  # raiz sem sentinela; so projects: deve ser considerado
  cat > "$proj/.qg.yaml" <<EOF
projects:
  - path: backend
    lang: go
  - path: frontend
EOF
  cd "$proj"
  run "$root/qg" --base origin/main --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.results | length == 2'
  echo "$output" | jq -e '[.results[].language] | sort == ["go","nodejs"]'
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: .qg.yaml projects: chave desconhecida -> exit 2" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  cat > "$proj/.qg.yaml" <<EOF
projects:
  - path: backend
    bogus: value
EOF
  cd "$proj"
  run "$root/qg" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *".qg.yaml"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: repassa --base e --format intactos pro gate" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  mkdir -p "$root/go"
  cp "$QG_REPO_ROOT/qg" "$root/qg"; chmod +x "$root/qg"
  cat > "$root/go/qg.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
for a in "$@"; do [ "$a" = "--detect" ] && { [ -f ./GO_SENTINEL ] && { echo go; exit 0; }; exit 1; }; done
echo "ARGS: $*" >&2
echo '{"schema_version":"1.1","mode":"comparative","language":"go","branch":"x","base_ref":"origin/develop","started_at":"2026-05-15T10:00:00Z","duration_seconds":1,"verdict":"passed","bypass_reason":null,"metrics":[]}'
exit 0
EOF
  chmod +x "$root/go/qg.sh"
  cd "$proj"; touch GO_SENTINEL
  run --separate-stderr "$root/qg" --base origin/develop --format json
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"--base origin/develop"* ]]
  [[ "$stderr" == *"--format json"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}
