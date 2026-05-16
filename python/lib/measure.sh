#!/usr/bin/env bash
# Funcoes de medicao do gate Python.
# Source este arquivo a partir de python/qg.sh.
# Cada funcao SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.
# measure_coverage retorna decimal.

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

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. ruff config
# do projeto-alvo (pyproject.toml [tool.ruff], ruff.toml) e IGNORADA. Override
# SO via env externa QG_RULESET_DIR -- NUNCA de .qg.yaml/arquivo do projeto.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: python.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] \
    || [ -f "$dir/setup.cfg" ] || ls "$dir"/requirements*.txt >/dev/null 2>&1
}

# Manager declarado pelo lockfile e autoritativo (LEI): se ha um lockfile
# de poetry/pdm/uv/pipenv mas o manager correspondente nao esta no PATH,
# isso e tool-error -- NUNCA cair em pip (resolver diferente => resolucao
# incorreta, peer-deps/markers divergentes, e erro enganoso). So
# requirements*.txt/pyproject sem lock => pip e legitimo.
# Resolve usando o manager do lockfile e retorna; sem lock, return 2 (segue
# o fluxo pip/venv legado do chamador).
qg_resolve_lock_manager() {
  local dir="$1" log="$2"
  if [ -f "$dir/poetry.lock" ]; then
    if ! command -v poetry >/dev/null 2>&1; then
      echo "::error::poetry.lock presente mas 'poetry' nao encontrado no PATH -- instale: 'pipx install poetry' (Linux) / 'brew install poetry' (macOS) (lockfile do projeto exige poetry; fallback para pip produziria resolucao incorreta)" >> "$log"
      return 1
    fi
    ( cd "$dir" && poetry install --no-interaction --no-ansi ) >> "$log" 2>&1 || return 1
    return 0
  elif [ -f "$dir/pdm.lock" ]; then
    if ! command -v pdm >/dev/null 2>&1; then
      echo "::error::pdm.lock presente mas 'pdm' nao encontrado no PATH -- instale: 'pipx install pdm' (Linux) / 'brew install pdm' (macOS) (lockfile do projeto exige pdm; fallback para pip produziria resolucao incorreta)" >> "$log"
      return 1
    fi
    ( cd "$dir" && pdm install ) >> "$log" 2>&1 || return 1
    return 0
  elif [ -f "$dir/uv.lock" ]; then
    if ! command -v uv >/dev/null 2>&1; then
      echo "::error::uv.lock presente mas 'uv' nao encontrado no PATH -- instale: 'curl -LsSf https://astral.sh/uv/install.sh | sh' (Linux) / 'brew install uv' (macOS) (lockfile do projeto exige uv; fallback para pip produziria resolucao incorreta)" >> "$log"
      return 1
    fi
    ( cd "$dir" && uv sync --frozen ) >> "$log" 2>&1 || return 1
    return 0
  elif [ -f "$dir/Pipfile.lock" ]; then
    if ! command -v pipenv >/dev/null 2>&1; then
      echo "::error::Pipfile.lock presente mas 'pipenv' nao encontrado no PATH -- instale: 'pipx install pipenv' (Linux) / 'brew install pipenv' (macOS) (lockfile do projeto exige pipenv; fallback para pip produziria resolucao incorreta)" >> "$log"
      return 1
    fi
    ( cd "$dir" && pipenv sync ) >> "$log" 2>&1 || return 1
    return 0
  fi
  return 2
}

# Bug 1: resolve o closure de dependencias antes de medir build/test.
# Cria venv efemera e instala deps. Falha = tool-error (return 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  # Se ha venv ativa, assume deps disponiveis.
  [ -n "${VIRTUAL_ENV:-}" ] && return 0
  # Lockfile autoritativo: manager do lock ausente = tool-error, nunca pip.
  local lockrc
  qg_resolve_lock_manager "$dir" "$log"; lockrc=$?
  if [ "$lockrc" -eq 1 ]; then
    return 1
  elif [ "$lockrc" -eq 0 ]; then
    return 0
  fi
  # lockrc == 2: sem lockfile de manager -> pip/venv legado.
  local req
  req=$(ls "$dir"/requirements*.txt 2>/dev/null | head -1)
  # Pacote instalavel = setup.py OU pyproject.toml com [build-system]/[project].
  # pyproject.toml so de config de tooling (ruff/pytest) NAO eh instalavel.
  local installable=0
  if [ -f "$dir/setup.py" ]; then
    installable=1
  elif [ -f "$dir/pyproject.toml" ] \
       && grep -qE '^\[(build-system|project)\]' "$dir/pyproject.toml" 2>/dev/null \
       && grep -qE '^\[build-system\]' "$dir/pyproject.toml" 2>/dev/null; then
    installable=1
  fi
  [ -z "$req" ] && [ "$installable" -eq 0 ] && return 0

  local venv="$dir/.qg-venv"
  if [ ! -d "$venv" ]; then
    ( cd "$dir" && python3 -m venv .qg-venv ) >> "$log" 2>&1 || return 1
  fi
  if [ -n "$req" ]; then
    ( cd "$dir" && "$venv/bin/pip" install -q -r "$req" ) >> "$log" 2>&1 || return 1
  fi
  if [ "$installable" -eq 1 ]; then
    ( cd "$dir" && "$venv/bin/pip" install -q . ) >> "$log" 2>&1 || return 1
  fi
  return 0
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: --config aponta para o ruff.toml do QG. Quando --config
  # eh um arquivo explicito, ruff NAO descobre o pyproject.toml/ruff.toml do
  # projeto-alvo -> config afrouxada do dev e ignorada.
  ( cd "$dir" && ruff format --check \
      --config "$rules/ruff.toml" . ) > "$log" 2>&1 || true
  # ruff format imprime "Would reformat: <path>" para cada arquivo divergente.
  _grep_count '^Would reformat: ' "$log"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: --config explicito do QG -> ruff ignora pyproject.toml /
  # ruff.toml do projeto-alvo.
  ( cd "$dir" && ruff check --config "$rules/ruff.toml" \
      --output-format=concise . ) > "$log" 2>&1 || true
  # ruff check --output-format=concise imprime UMA linha por issue:
  # path:linha:col: CODIGO mensagem
  _grep_count '^[^:[:space:]]+:[0-9]+:[0-9]+: [A-Z][0-9]+' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  # compileall reporta erros de sintaxe (modo -q so imprime erros).
  ( cd "$dir" && python3 -m compileall -q . ) > "$log" 2>&1 || true
  # Cada erro vem em forma de bloco; "SyntaxError" ou "Sorry: ..." indica falha.
  # Conta linhas iniciando por '*** ' (compileall) OU 'SyntaxError'.
  local n
  n=$(grep -cE '^(\*\*\* |SyntaxError:|Sorry:)' "$log" 2>/dev/null | head -1)
  [ -z "$n" ] && n=0
  printf '%d\n' "${n:-0}"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  # -p no:cacheprovider para evitar criar .pytest_cache no fixture
  ( cd "$dir" && pytest -p no:cacheprovider --tb=no -q ) > "$log" 2>&1 || true
  # Cada teste falhado gera linha "FAILED test_xxx::yyy" em modo -q.
  _grep_count '^FAILED ' "$log"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  # LEI (docs/contract.md): mede CODIGO-FONTE. radon nao tem arquivo de
  # config -> ignore CANONICO do QG via -i (dirs) e -e (file globs),
  # alinhado ao extend-exclude do ruff.toml. NUNCA le ignore do projeto.
  local _qg_radon_ignore='node_modules,dist,build,out,.next,.nuxt,.expo,coverage,.turbo,.cache,.venv,venv'
  local _qg_radon_exclude='*/node_modules/*,*/dist/*,*/build/*,*/out/*,*/.next/*,*/.nuxt/*,*/.expo/*,*/coverage/*,*/.turbo/*,*/.cache/*,*/.venv/*,*/venv/*'
  ( cd "$dir" && radon cc -n C -s -i "$_qg_radon_ignore" -e "$_qg_radon_exclude" . ) > "$log" 2>&1 || true
  # radon cc -n C lista funcoes acima de complexidade C (>= 11).
  # Formato: "    F LINHA:COL nome - GRAU (cc)" -- conta linhas com indentacao + grau.
  _grep_count '^[[:space:]]+[CFM] [0-9]+:[0-9]+ ' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  ( cd "$dir" && pytest -p no:cacheprovider --cov=. --cov-report=json:"$out" --tb=no -q ) >/dev/null 2>&1 || true
  local pct=0
  if [ -s "$out" ]; then
    pct=$(jq -r '.totals.percent_covered // 0' "$out" 2>/dev/null || echo 0)
  fi
  # Bug 2: nunca retorna vazio/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}
