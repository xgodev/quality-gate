#!/usr/bin/env bash
# Funções de medição do gate Rust.
# Source este arquivo a partir de rust/qg.sh.
# Cada função SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.

_grep_count() {
  local pattern="$1" file="$2"
  local n
  if n=$(grep -cE "$pattern" "$file" 2>/dev/null); then
    :
  else
    n=0
  fi
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

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. clippy.toml /
# rustfmt.toml do projeto-alvo sao IGNORADOS. Override SO via env externa
# QG_RULESET_DIR (setada por quem RODA o gate) -- NUNCA de .qg.yaml/arquivo
# do projeto. Default = rules/ embarcado no QG.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: rust.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/Cargo.toml" ]
}

# rust-toolchain.toml/rust-toolchain e autoritativo (LEI): pina o channel
# que o projeto usa. cargo/rustup honram o arquivo NATIVAMENTE -- o gate
# NUNCA injeta `+stable`/override que ignore o arquivo. Se o channel pinado
# nao esta instalado e o rustup nao consegue instalar (offline) => tool-error
# claro, NUNCA build com stable do sistema.
# Retorna 0 se honravel/sem pin; 1 = tool-error (msg no $log).
qg_check_rust_toolchain() {
  local dir="$1" log="$2"
  local tf="" channel=""
  if [ -f "$dir/rust-toolchain.toml" ]; then
    tf="$dir/rust-toolchain.toml"
    channel=$(grep -E '^[[:space:]]*channel[[:space:]]*=' "$tf" 2>/dev/null \
              | head -1 | sed -E 's/.*=[[:space:]]*"?([^"#]+)"?.*/\1/' \
              | tr -d '[:space:]')
  elif [ -f "$dir/rust-toolchain" ]; then
    tf="$dir/rust-toolchain"
    channel=$(head -1 "$tf" 2>/dev/null | tr -d '[:space:]')
  fi
  [ -z "$channel" ] && return 0
  command -v rustup >/dev/null 2>&1 || return 0
  # Channel pinado ja instalado? rustup toolchain list lista as instaladas.
  if rustup toolchain list 2>/dev/null | grep -q "^${channel}\b\|^${channel}-"; then
    return 0
  fi
  # Nao instalado: so e seguro se rustup conseguir instalar (online). Testa
  # sem efeito colateral pesado: tentar resolver a versao remota.
  if ! rustup run "$channel" rustc --version >/dev/null 2>&1; then
    echo "::error::rust-toolchain pina channel '${channel}' nao instalado e rustup nao consegue instala-lo (offline?) -- instale: 'rustup toolchain install ${channel}' (Linux) / 'rustup toolchain install ${channel}' (macOS) (build com stable do sistema mediria artefato incorreto)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: cargo resolve dependencias sozinho no build/test. cargo/rustup
# honram rust-toolchain.toml nativamente -- NAO injetar `+stable`/override.
# Falha de resolucao = tool-error.
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  [ -f "$dir/Cargo.toml" ] || return 0
  qg_check_rust_toolchain "$dir" "$log" || return 1
  # Sem `+toolchain`: cargo honra rust-toolchain.toml por si.
  ( cd "$dir" && cargo fetch ) >> "$log" 2>&1 || return 1
  return 0
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: rustfmt aponta para o rustfmt.toml do QG, ignorando o
  # do projeto-alvo.
  ( cd "$dir" && cargo fmt --all -- --check \
      --config-path "$rules/rustfmt.toml" ) > "$log" 2>&1 || true
  _grep_count '^Diff in ' "$log"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: clippy le clippy.toml de CLIPPY_CONF_DIR -> ruleset do QG.
  (
    cd "$dir" && CLIPPY_CONF_DIR="$rules" cargo clippy --all-targets -- \
      -D warnings \
      -A clippy::cognitive_complexity \
      -A clippy::too_many_lines \
      -A clippy::too_many_arguments \
      -A clippy::type_complexity
  ) > "$log" 2>&1 || true
  _grep_count '^error(\[|:)' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && cargo build --all-targets ) > "$log" 2>&1 || true
  _grep_count '^error(\[|:)' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && cargo test --all-targets --no-fail-fast ) > "$log" 2>&1 || true
  local n
  n=$(grep -E '^test result:' "$log" 2>/dev/null \
      | sed -E 's/.*([0-9]+) failed.*/\1/' \
      | awk '{ s += $1 } END { print s+0 }')
  printf '%d\n' "${n:-0}"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: thresholds de complexidade vem do clippy.toml do QG
  # (CLIPPY_CONF_DIR), nunca do projeto-alvo.
  (
    cd "$dir" && CLIPPY_CONF_DIR="$rules" cargo clippy --all-targets -- \
      -A clippy::all \
      -W clippy::cognitive_complexity \
      -W clippy::too_many_lines \
      -W clippy::too_many_arguments \
      -W clippy::type_complexity
  ) > "$log" 2>&1 || true
  _grep_count 'cognitive complexity|too many lines|too many arguments|type complexity' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  ( cd "$dir" && cargo llvm-cov --json --output-path "$out" ) >/dev/null 2>&1 || true
  local pct=0
  if [ -s "$out" ]; then
    pct=$(jq -r '.data[0].totals.lines.percent // 0' "$out" 2>/dev/null || echo 0)
  fi
  # Bug 2: nunca retorna vazio/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}
