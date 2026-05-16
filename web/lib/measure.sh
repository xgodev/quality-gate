#!/usr/bin/env bash
# Funcoes de medicao do gate web (HTML + CSS estatico puro).
# Source este arquivo a partir de web/qg.sh.
# Cada funcao SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.
#
# OBSERVACAO: este gate mede APENAS fmt + lint. As metricas build, test,
# complexity e coverage sao OMITIDAS -- HTML/CSS estatico nao tem conceito
# de build/test/complexidade/cobertura. Documentado em docs/languages/web.md.
# (Igual Swift omite complexity -- o contrato permite omissao documentada.)

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

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. .stylelintrc /
# .htmlhintrc / .prettierrc do projeto-alvo sao IGNORADOS. Override SO via env
# externa QG_RULESET_DIR -- NUNCA de .qg.yaml/arquivo do projeto.
# Base absoluta capturada no SOURCE-TIME (antes de qualquer cd), robusta a
# mudanca de cwd e a source com path relativo.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: web.
# Presenca de *.html / *.css / *.scss na raiz E ausencia de package.json
# (se ha package.json e projeto nodejs -> nodejs/qg.sh cobre HTML/CSS dele).
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/package.json" ] && return 1
  ls "$dir"/*.html  >/dev/null 2>&1 && return 0
  ls "$dir"/*.htm   >/dev/null 2>&1 && return 0
  ls "$dir"/*.css   >/dev/null 2>&1 && return 0
  ls "$dir"/*.scss  >/dev/null 2>&1 && return 0
  return 1
}

# web nao tem gerenciador de deps -> no-op de simetria (contrato Bug 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  return 0
}

# fontes HTML/CSS/SCSS. LEI (docs/contract.md): mede CODIGO-FONTE -- exclui
# dirs gerados/vendored pelo ignore CANONICO do QG (mesma lista de
# web/rules/.prettierignore), nunca config do projeto-alvo.
_qg_web_excl_re='^\./(node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/'
_qg_web_html() {
  ( cd "$1" && find . \
      \( -path './node_modules' -prune -o -path './dist' -prune \
         -o -path './build' -prune -o -path './out' -prune \
         -o -path './.next' -prune -o -path './.nuxt' -prune \
         -o -path './.expo' -prune -o -path './coverage' -prune \
         -o -path './.turbo' -prune -o -path './.cache' -prune \) \
      -o -type f -name '*.html' -print 2>/dev/null ) \
      | grep -vE "$_qg_web_excl_re"
}
_qg_web_css() {
  ( cd "$1" && find . \
      \( -path './node_modules' -prune -o -path './dist' -prune \
         -o -path './build' -prune -o -path './out' -prune \
         -o -path './.next' -prune -o -path './.nuxt' -prune \
         -o -path './.expo' -prune -o -path './coverage' -prune \
         -o -path './.turbo' -prune -o -path './.cache' -prune \) \
      -o -type f \( -name '*.css' -o -name '*.scss' \) -print 2>/dev/null ) \
      | grep -vE "$_qg_web_excl_re" | grep -vE '\.min\.css$'
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: --config do QG + --no-editorconfig (ignora .prettierrc
  # e .editorconfig do projeto-alvo). --ignore-path aponta para o
  # .prettierignore CANONICO do QG (NUNCA o do projeto): LEI -- mede
  # CODIGO-FONTE, dirs gerados/vendored ficam de fora. Verifica HTML+CSS+SCSS.
  ( cd "$dir" && npx --yes prettier --check \
      --config "$rules/.prettierrc.json" --no-editorconfig \
      --ignore-path "$rules/.prettierignore" \
      "**/*.{html,css,scss}" ) > "$log" 2>&1 || true
  # prettier emite "[warn] <path>" para cada arquivo divergente. Filtro
  # defensivo: mesmo se prettier nao honrar bem o --ignore-path, paths
  # gerados/minificados nao entram na contagem.
  local n
  n=$(grep -E '^\[warn\] [^[:space:]].*\.(html|css|scss)$' "$log" 2>/dev/null \
    | grep -vE '^\[warn\] (.*/)?(node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/' \
    | grep -vcE '\.min\.css$')
  printf '%d\n' "$(_num "${n:-0}")"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules total=0
  rules=$(qg_ruleset_dir)

  # stylelint (CSS/SCSS) -- ruleset do QG, ignora config do projeto.
  local css_files
  css_files=$(_qg_web_css "$dir")
  if [ -n "$css_files" ]; then
    # stylelint: --config aponta arquivo explicito -> ignora .stylelintrc do
    # projeto (stylelint nao tem --no-config-lookup; --config ja sobrepoe).
    # Passa a lista EXPLICITA de fontes (ja filtrada por _qg_web_css com o
    # ignore canonico) em vez de glob "**/*" -- LEI: nunca varrer dirs
    # gerados/vendored nem *.min.css.
    ( cd "$dir" && printf '%s\n' "$css_files" \
        | xargs npx --yes stylelint \
        --config "$rules/.stylelintrc.json" ) > "$log.style" 2>&1 || true
    local s
    # stylelint default formatter: linhas " N:N  ✖  msg  rule".
    s=$(_grep_count '^[[:space:]]+[0-9]+:[0-9]+' "$log.style")
    total=$((total + s))
    cat "$log.style" >> "$log"
    rm -f "$log.style"
  fi

  # htmlhint (HTML) -- ruleset do QG, ignora .htmlhintrc do projeto.
  local html_files
  html_files=$(_qg_web_html "$dir")
  if [ -n "$html_files" ]; then
    # Lista EXPLICITA (ja filtrada por _qg_web_html com o ignore canonico)
    # em vez de glob "**/*.html" -- LEI: nunca varrer dirs gerados/vendored.
    ( cd "$dir" && printf '%s\n' "$html_files" \
        | xargs npx --yes htmlhint \
        --config "$rules/.htmlhintrc" ) > "$log.html" 2>&1 || true
    local h
    # htmlhint resumo: "N errors in M files" / linhas "L:C msg".
    h=$(awk '
      /[0-9]+ (error|errors) in [0-9]+ (file|files)/ {
        for (i=1; i<=NF; i++) if ($(i+1) == "error" || $(i+1) == "errors") { print $i; exit }
      }
    ' "$log.html")
    h=$(_num "$h")
    total=$((total + h))
    cat "$log.html" >> "$log"
    rm -f "$log.html"
  fi

  printf '%d\n' "$total"
}
