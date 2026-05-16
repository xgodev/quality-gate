#!/usr/bin/env bash
# Funcoes de medicao do gate Swift (SwiftPM).
# Source este arquivo a partir de swift/qg.sh.
# Cada funcao SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.
#
# OBSERVACAO: a metrica `complexity` NAO eh implementada para Swift -- nao ha
# ferramenta canonica estavel (swiftlint cyclomatic_complexity existe mas o threshold
# nao eh customizavel de forma simples e o conjunto de regras de "complexity" varia
# entre versoes). Documentado em docs/languages/swift.md.

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

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. .swiftlint.yml
# / .swift-format do projeto-alvo sao IGNORADOS. Override SO via env externa
# QG_RULESET_DIR -- NUNCA de .qg.yaml/arquivo do projeto.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: swift.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/Package.swift" ]
}

# swift-tools-version do Package.swift e autoritativo (LEI): a 1a linha
# `// swift-tools-version:X.Y` declara a versao minima do toolchain SwiftPM
# que o projeto exige. Se o `swift` do PATH e mais antigo, SwiftPM falha com
# erro confuso -- o gate emite tool-error claro, NUNCA build degradado.
# Retorna 0 se honravel/sem declaracao; 1 = tool-error (msg no $log).
qg_check_swift_tools_version() {
  local dir="$1" log="$2"
  command -v swift >/dev/null 2>&1 || return 0
  local required
  required=$(head -1 "$dir/Package.swift" 2>/dev/null \
    | sed -E 's@^//[[:space:]]*swift-tools-version:?[[:space:]]*([0-9]+\.[0-9]+).*@\1@' )
  # Sem match valido (linha nao e a diretiva) => nada a checar.
  printf '%s' "$required" | grep -qE '^[0-9]+\.[0-9]+$' || return 0
  local have
  have=$( swift --version 2>/dev/null \
    | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1 )
  [ -z "$have" ] && return 0
  local norm_req norm_have
  norm_req=$( printf '%s' "$required" | awk -F. '{printf "%03d%03d", $1, $2}' )
  norm_have=$( printf '%s' "$have" | awk -F. '{printf "%03d%03d", $1, $2}' )
  if [ "$norm_have" -lt "$norm_req" ]; then
    echo "::error::Package.swift declara swift-tools-version:${required} mas o 'swift' do PATH e ${have} (mais antigo) -- instale Swift >= ${required} (build com toolchain abaixo do declarado mediria artefato incorreto)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: SwiftPM resolve sozinho no swift build. Sem mudanca; mantido por
# simetria de contrato. Falha de resolucao = tool-error (return 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  [ -f "$dir/Package.swift" ] || return 0
  qg_check_swift_tools_version "$dir" "$log" || return 1
  ( cd "$dir" && swift package resolve ) >> "$log" 2>&1 || return 1
  return 0
}

# Lista de fontes Swift sob Sources/ e Tests/ (excluindo .build).
_qg_swift_sources() {
  local dir="$1"
  find "$dir" -type d -name '.build' -prune -o -type f -name '*.swift' -print 2>/dev/null \
    | grep -vE '/\.build/'
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local errors=0
  local files
  files=$(_qg_swift_sources "$dir")
  if [ -z "$files" ]; then
    printf '0\n'
    return
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # swift-format lint imprime warnings; --strict transforma em exit !=0.
    # $f ja vem com o path completo a partir de $dir -> NAO fazer cd (senao
    # o path relativo nao resolve no novo cwd). Tamper: --configuration do QG.
    local out
    out=$( swift-format lint --strict \
        --configuration "$(qg_ruleset_dir)/.swift-format" "$f" 2>&1 )
    if [ -n "$out" ]; then
      echo "$f" >> "$log"
      errors=$((errors + 1))
    fi
  done <<< "$files"
  printf '%d\n' "$errors"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "::error::swiftlint nao encontrado -- instale: 'git clone https://github.com/realm/SwiftLint && cd SwiftLint && swift build -c release && cp .build/release/swiftlint /usr/local/bin/' (Linux) / 'brew install swiftlint' (macOS) (sem swiftlint a metrica lint nao roda)" >&2
    printf '0\n'
    return
  fi
  # Tamper-resistance: --config do QG, ignorando .swiftlint.yml do projeto.
  # Passa as fontes explicitamente (exclui .build/ -- artefato de build
  # gerado, NUNCA codigo do projeto; swiftlint resolve `excluded` relativo
  # ao --config, entao nao basta a chave excluded no ruleset).
  local rules
  rules=$(qg_ruleset_dir)
  # Lint so as fontes reais (Sources/Tests), passadas explicitamente, para
  # nunca varrer .build/ (codigo gerado). swiftlint aceita paths posicionais.
  local -a srcs=()
  while IFS= read -r f; do
    [ -n "$f" ] && srcs+=("$f")
  done < <(_qg_swift_sources "$dir")
  if [ ${#srcs[@]} -eq 0 ]; then
    printf '0\n'
    return
  fi
  swiftlint lint --no-cache --quiet \
    --config "$rules/.swiftlint.yml" "${srcs[@]}" > "$log" 2>&1 || true
  # swiftlint imprime: path:linha:col: warning|error: msg (rule)
  _grep_count '\.swift:[0-9]+:[0-9]+: (warning|error):' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && swift build ) > "$log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '0\n'
    return
  fi
  # swiftc imprime "path:linha:col: error: msg"
  _grep_count '\.swift:[0-9]+:[0-9]+: error:' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && swift test --enable-code-coverage ) > "$log" 2>&1 || true
  # XCTest imprime "Executed N tests, with F failures (UF unexpected)" no resumo.
  # Soma todos os "with F failures" -- pega a ultima ocorrencia (resumo all tests).
  local n
  n=$(awk '
    /Executed [0-9]+ tests?, with [0-9]+ failures?/ {
      for (i=1; i<=NF; i++) {
        if ($i == "with") { last_fail = $(i+1); found = 1 }
      }
    }
    END {
      if (found) print last_fail + 0
      else print 0
    }
  ' "$log")
  [ -z "$n" ] && n=0
  printf '%d\n' "$n"
}

# count_complexity OMITIDA -- ver header do arquivo + docs/languages/swift.md.

measure_coverage() {
  local dir="$1" out="$2"
  # swift test --enable-code-coverage gera profraw files em .build/<arch>/debug/codecov/.
  # Quando os testes PASSAM, swift gera tambem default.profdata + JSONs por modulo.
  # Quando FALHAM, so os profraw existem -- precisamos gerar profdata manualmente.
  ( cd "$dir" && swift test --enable-code-coverage ) >/dev/null 2>&1 || true
  local cov_dir
  cov_dir=$(find "$dir/.build" -type d -name codecov 2>/dev/null | head -1)
  if [ -z "$cov_dir" ]; then
    printf '{"coverage_percent": 0}\n' > "$out"
    printf '0\n'
    return
  fi

  # Merge profraw -> profdata se ainda nao existe ou se ha profraw novos.
  local profdata="$cov_dir/default.profdata"
  if [ ! -f "$profdata" ] || ls "$cov_dir"/*.profraw >/dev/null 2>&1; then
    if ls "$cov_dir"/*.profraw >/dev/null 2>&1; then
      xcrun llvm-profdata merge -sparse "$cov_dir"/*.profraw -o "$profdata" 2>/dev/null || true
    fi
  fi

  if [ ! -f "$profdata" ]; then
    printf '{"coverage_percent": 0}\n' > "$out"
    printf '0\n'
    return
  fi

  # Encontra o(s) binario(s) executavel xctest. Excluir contents/dSYM.
  # Convencao SwiftPM: <pkg>.xctest/Contents/MacOS/<pkg> (sem extensao, executavel).
  local binaries
  binaries=$(find "$dir/.build" -type d -name '*.xctest' 2>/dev/null | while read -r b; do
    pkg=$(basename "$b" .xctest)
    candidate="$b/Contents/MacOS/$pkg"
    [ -x "$candidate" ] && echo "$candidate"
  done)

  if [ -z "$binaries" ]; then
    printf '{"coverage_percent": 0}\n' > "$out"
    printf '0\n'
    return
  fi

  # Caminhos absolutos para nao depender do cwd da subshell xcrun.
  local abs_dir
  abs_dir=$(cd "$dir" && pwd)
  local abs_profdata
  abs_profdata=$(cd "$(dirname "$profdata")" && pwd)/$(basename "$profdata")

  # Soma totals de cada binario (cobre os modulos do projeto).
  local total_count=0
  local total_covered=0
  while IFS= read -r bin; do
    [ -z "$bin" ] && continue
    local abs_bin
    abs_bin=$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")
    local json
    # Filtra para Sources/ (exclui test code) -- comparavel com outras linguagens.
    json=$(xcrun llvm-cov export -summary-only \
              -instr-profile="$abs_profdata" "$abs_bin" "$abs_dir/Sources" 2>/dev/null)
    [ -z "$json" ] && continue
    local c cov
    c=$(echo "$json" | jq -r '.data[0].totals.lines.count // 0' 2>/dev/null || echo 0)
    cov=$(echo "$json" | jq -r '.data[0].totals.lines.covered // 0' 2>/dev/null || echo 0)
    total_count=$(awk -v a="$total_count" -v b="$c" 'BEGIN { print a+b }')
    total_covered=$(awk -v a="$total_covered" -v b="$cov" 'BEGIN { print a+b }')
  done <<< "$binaries"

  local pct=0
  if [ "$total_count" != "0" ]; then
    pct=$(LC_ALL=C awk -v c="$total_covered" -v t="$total_count" 'BEGIN { printf "%.2f", (c*100.0)/t }')
  fi
  pct=$(_num "$pct")
  printf '{"total_count": %s, "total_covered": %s, "coverage_percent": %s}\n' \
    "$(_num "$total_count")" "$(_num "$total_covered")" "$pct" > "$out"
  # Bug 2: nunca retorna vazio/"Unknown" -> 0.
  printf '%s\n' "$pct"
}
