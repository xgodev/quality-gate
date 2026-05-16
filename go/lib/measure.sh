#!/usr/bin/env bash
# Funcoes de medicao do gate Go.
# Source este arquivo a partir de go/qg.sh.
# Cada funcao SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.
# measure_coverage retorna decimal (ex: 82.50).

_grep_count() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -cE "$pattern" "$file" 2>/dev/null | head -1)
  [ -z "$n" ] && n=0
  printf '%d\n' "${n:-0}"
}

# Garante numero; qualquer coisa nao-numerica (vazio, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. .golangci.yml
# do projeto-alvo e IGNORADO. Override SO via env externa QG_RULESET_DIR
# (setada por quem RODA o gate) -- NUNCA de .qg.yaml/arquivo do projeto.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: go.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/go.mod" ]
}

# Toolchain declarado em go.mod e autoritativo (LEI): a diretiva
# `toolchain`/`go 1.x` do go.mod pina a versao do Go que o projeto usa.
# GOTOOLCHAIN=auto (default) baixa a pinada; o gate NUNCA forca
# GOTOOLCHAIN=local (que ignoraria a pinada e construiria com a versao do
# PATH). Se a versao pinada nao e satisfazivel (download falhou offline,
# GOTOOLCHAIN=local externo) e a versao do PATH diverge da pinada, isso e
# tool-error -- nunca build silencioso com versao errada.
# Retorna 0 se honravel/sem pin; 1 = tool-error (msg no $log).
qg_check_go_toolchain() {
  local dir="$1" log="$2"
  command -v go >/dev/null 2>&1 || return 0
  local pinned path_ver
  # Diretiva `toolchain go1.x.y` tem prioridade; senao a diretiva `go 1.x`.
  pinned=$(grep -E '^toolchain[[:space:]]+go[0-9]' "$dir/go.mod" 2>/dev/null \
            | head -1 | sed -E 's/^toolchain[[:space:]]+go//')
  if [ -z "$pinned" ]; then
    pinned=$(grep -E '^go[[:space:]]+[0-9]' "$dir/go.mod" 2>/dev/null \
              | head -1 | sed -E 's/^go[[:space:]]+//')
  fi
  [ -z "$pinned" ] && return 0
  # Se GOTOOLCHAIN=local (externo), o go NAO baixa a pinada -- so e seguro se
  # a versao do PATH satisfaz a pinada.
  local gotc="${GOTOOLCHAIN:-auto}"
  case "$gotc" in
    local)
      path_ver=$( go version 2>/dev/null | sed -E 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/' )
      # Comparacao de versao major.minor.patch (zero-padded por campo).
      local norm_pin norm_path
      norm_pin=$( printf '%s' "$pinned" | awk -F. '{printf "%03d%03d%03d", $1, $2, ($3==""?0:$3)}' )
      norm_path=$( printf '%s' "$path_ver" | awk -F. '{printf "%03d%03d%03d", $1, $2, ($3==""?0:$3)}' )
      if [ -n "$path_ver" ] && [ "$norm_path" -lt "$norm_pin" ]; then
        echo "::error::go.mod pina toolchain go${pinned} mas GOTOOLCHAIN=local e o go do PATH e ${path_ver} (mais antigo) -- remova GOTOOLCHAIN=local ou instale Go ${pinned} (build com versao divergente da pinada produziria resultado incorreto)" >> "$log"
        return 1
      fi
      ;;
  esac
  return 0
}

# Bug 1: resolve o closure de dependencias antes de medir build/test.
# go modules resolvem em build/test, mas garantimos GOFLAGS=-mod=mod e
# pre-baixamos. Falha de download = tool-error (return 1); chamador exit 2.
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  [ -f "$dir/go.mod" ] || return 0
  qg_check_go_toolchain "$dir" "$log" || return 1
  # Nao forca GOTOOLCHAIN: respeita o ambiente (default auto baixa a pinada).
  ( cd "$dir" && GOFLAGS=-mod=mod go mod download ) >> "$log" 2>&1 || return 1
  return 0
}

# Detecta qual binario de lint usar.
# Preferimos golangci-lint, com fallback para go vet (sempre presente).
# QG_GO_LINT_FORCE_VET=1 forca go vet (util para CI/dev sem golangci-lint).
_qg_go_lint_tool() {
  if [ -n "${QG_GO_LINT_FORCE_VET:-}" ]; then
    echo "go-vet"
    return
  fi
  if command -v golangci-lint >/dev/null 2>&1; then
    echo "golangci-lint"
    return
  fi
  echo "go-vet"
}

# Ignore CANONICO do QG (dirs gerados/vendored). LEI (docs/contract.md):
# fmt/lint/complexity medem CODIGO-FONTE. gofmt/gocyclo varrem `.` recursivo
# e NAO pulam vendor/build/dist -- aplicamos a exclusao no output (alinhado
# ao .prettierignore do nodejs; em Go, `vendor/` e o caso classico).
# Casa o dir gerado/vendored como componente de path em qualquer posicao da
# linha: precedido por inicio-de-linha, espaco ou `/` (gocyclo imprime
# "CICLO PKG FUNC build/gen.go:..."; gofmt imprime "build/gen.go").
_qg_go_excl_re='(^|/|[[:space:]])(vendor|node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/'

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && gofmt -l . ) > "$log" 2>&1 || true
  # gofmt -l imprime UM caminho por linha para cada arquivo desformatado.
  # Exclui dirs gerados/vendored (vendor/, build/, etc.) -- mede fonte.
  local n
  n=$(grep -E '\.go$' "$log" 2>/dev/null \
    | grep -vcE "$_qg_go_excl_re")
  printf '%d\n' "$(_num "${n:-0}")"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local tool
  tool=$(_qg_go_lint_tool)
  if [ "$tool" = "golangci-lint" ]; then
    local rules
    rules=$(qg_ruleset_dir)
    # Tamper-resistance: -c aponta para o .golangci.yml do QG, ignorando o
    # do projeto-alvo.
    ( cd "$dir" && golangci-lint run -c "$rules/.golangci.yml" \
        --out-format=line-number ./... ) > "$log" 2>&1
    local rc=$?
    # Tool failure (rc != 0 e != 1) -> sem issues, mas registra warning e usa vet como sanity.
    # rc=0 sem issues, rc=1 issues encontrados. Outros codigos = problema com o linter.
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      echo "::warning::golangci-lint retornou exit $rc -- possivel incompatibilidade de versao; usando go vet como fallback" >&2
      ( cd "$dir" && go vet ./... ) > "$log" 2>&1 || true
      _grep_count '\.go:[0-9]+:[0-9]+:' "$log"
      return
    fi
    # Linhas no formato path/file.go:LINHA:COL: msg (linter)
    _grep_count '^[^:[:space:]]+\.go:[0-9]+:[0-9]+:' "$log"
  else
    ( cd "$dir" && go vet ./... ) > "$log" 2>&1 || true
    # go vet imprime path/file.go:LINHA:COL: msg
    _grep_count '\.go:[0-9]+:[0-9]+:' "$log"
  fi
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && GOFLAGS=-mod=mod go build ./... ) > "$log" 2>&1 || true
  # go build imprime erros como path/file.go:LINHA:COL: erro
  _grep_count '\.go:[0-9]+:[0-9]+:' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  # -vet=off para nao duplicar com count_lint_errors
  ( cd "$dir" && GOFLAGS=-mod=mod go test ./... -count=1 -vet=off ) > "$log" 2>&1 || true
  # Tool error vs test failure: panic do runner deveria gerar exit !=0/1 e mensagens diferentes.
  # Aqui contamos linhas "--- FAIL:" (cada teste falhado).
  _grep_count '^--- FAIL:' "$log"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  if ! command -v gocyclo >/dev/null 2>&1; then
    echo "::error::gocyclo nao encontrado -- instale: 'go install github.com/fzipp/gocyclo/cmd/gocyclo@latest' (Linux) / 'go install github.com/fzipp/gocyclo/cmd/gocyclo@latest' (macOS) (sem gocyclo a metrica complexity nao roda)" >&2
    printf '0\n'
    return
  fi
  # LEI (docs/contract.md): mede CODIGO-FONTE. -ignore (fzipp/gocyclo) pula
  # dirs gerados/vendored; filtro de output e defensivo (mesma lista do QG).
  ( cd "$dir" && gocyclo -over 15 \
      -ignore '(^|/)(vendor|node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/' \
      . ) > "$log" 2>&1 || true
  # gocyclo imprime UMA linha por funcao acima do threshold no formato:
  # CICLO PACOTE FUNCAO ARQUIVO:LINHA:COL
  local n
  n=$(grep -E '^[0-9]+ ' "$log" 2>/dev/null \
    | grep -vcE "$_qg_go_excl_re")
  printf '%d\n' "$(_num "${n:-0}")"
}

measure_coverage() {
  local dir="$1" out="$2"
  local profile
  profile="${out%.json}.profile"
  ( cd "$dir" && GOFLAGS=-mod=mod go test ./... -count=1 -vet=off -covermode=atomic -coverprofile="$profile" ) >/dev/null 2>&1 || true
  local pct=0
  if [ -s "$profile" ]; then
    # go tool cover -func gera linha "total: (statements) X.X%"
    pct=$( ( cd "$dir" && go tool cover -func="$profile" ) 2>/dev/null \
            | awk '/^total:/ { gsub("%","",$NF); print $NF; exit }')
  fi
  pct=$(_num "$pct")
  # Persiste log JSON-like para auditar
  printf '{"coverage_percent": %s}\n' "$pct" > "$out"
  # Bug 2: nunca retorna vazio/"Unknown" -> 0.
  printf '%s\n' "$pct"
}
