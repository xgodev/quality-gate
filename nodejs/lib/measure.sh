#!/usr/bin/env bash
# Funcoes de medicao do gate Node.js.
# Source este arquivo a partir de nodejs/qg.sh.
# Cada funcao SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.

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

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. Config do
# projeto-alvo (.eslintrc*, .prettierrc, tsconfig) e IGNORADA. Override SO
# via env externa QG_RULESET_DIR (setada por quem RODA o gate / pipeline)
# -- NUNCA lida de .qg.yaml/arquivo do projeto. Default = rules/ embarcado.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: nodejs.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/package.json" ]
}

# Bug 1: resolve o closure de dependencias antes de medir build/test.
# Falha de resolucao = tool-error (return 1); o chamador faz exit 2.
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  # So resolve se node_modules ausente OU lockfile mais novo que node_modules.
  local need=0
  if [ ! -d "$dir/node_modules" ]; then
    need=1
  else
    local lf
    for lf in pnpm-lock.yaml yarn.lock package-lock.json; do
      if [ -f "$dir/$lf" ] && [ "$dir/$lf" -nt "$dir/node_modules" ]; then
        need=1
        break
      fi
    done
  fi
  [ "$need" -eq 0 ] && return 0

  # Lockfile e autoritativo: gerenciador ausente vira tool-error claro,
  # NUNCA fallback para outro gerenciador (resolucao incorreta + erro enganoso).
  if [ -f "$dir/pnpm-lock.yaml" ]; then
    if ! command -v pnpm >/dev/null 2>&1; then
      echo "::error::pnpm-lock.yaml presente mas 'pnpm' nao encontrado no PATH -- instale: 'npm i -g pnpm' (Linux) / 'brew install pnpm' (macOS) (lockfile do projeto exige pnpm; fallback para npm produziria resolucao incorreta)" >> "$log"
      return 1
    fi
    ( cd "$dir" && pnpm i --frozen-lockfile ) >> "$log" 2>&1 || return 1
  elif [ -f "$dir/yarn.lock" ]; then
    if ! command -v yarn >/dev/null 2>&1; then
      echo "::error::yarn.lock presente mas 'yarn' nao encontrado no PATH -- instale: 'npm i -g yarn' (Linux) / 'brew install yarn' (macOS) (lockfile do projeto exige yarn; fallback para npm produziria resolucao incorreta)" >> "$log"
      return 1
    fi
    # Fix 3: .yarnrc.yml na raiz = Yarn Berry (v2+) -> 'yarn install
    # --immutable' (equivalente Berry de --frozen-lockfile; Berry NAO aceita
    # --frozen-lockfile). Sem .yarnrc.yml = Yarn classic (v1) ->
    # --frozen-lockfile. Yarn ausente continua tool-error (msg acima).
    if [ -f "$dir/.yarnrc.yml" ]; then
      ( cd "$dir" && yarn install --immutable ) >> "$log" 2>&1 || return 1
    else
      ( cd "$dir" && yarn install --frozen-lockfile ) >> "$log" 2>&1 || return 1
    fi
  elif [ -f "$dir/package-lock.json" ]; then
    ( cd "$dir" && npm ci ) >> "$log" 2>&1 || return 1
  else
    ( cd "$dir" && npm install ) >> "$log" 2>&1 || return 1
  fi
  return 0
}

# Glob de fontes JS/TS para iterar com node --check.
# LEI (docs/contract.md): mede CODIGO-FONTE -- exclui dirs gerados/vendored
# pelo ignore canonico do QG (mesma lista de nodejs/rules/.prettierignore),
# nunca config do projeto-alvo.
_qg_node_sources() {
  local dir="$1"
  ( cd "$dir" && find . \
      \( -path './node_modules' -prune -o -path './coverage' -prune \
         -o -path './dist' -prune -o -path './build' -prune \
         -o -path './out' -prune -o -path './.next' -prune \
         -o -path './.nuxt' -prune -o -path './.expo' -prune \
         -o -path './.turbo' -prune -o -path './.cache' -prune \) \
      -o -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print ) \
      | grep -vE '^\./(node_modules|coverage|dist|build|out|\.next|\.nuxt|\.expo|\.turbo|\.cache)/' \
      | grep -vE '\.(min|bundle|chunk)\.js$|\.map$'
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: --config do QG + --no-editorconfig (ignora .prettierrc
  # e .editorconfig do projeto-alvo). --ignore-path aponta para o
  # .prettierignore CANONICO do QG (NUNCA o do projeto): LEI -- mede
  # CODIGO-FONTE, dirs gerados/vendored ficam de fora.
  ( cd "$dir" && npx --yes prettier --check \
      --config "$rules/.prettierrc.json" --no-editorconfig \
      --ignore-path "$rules/.prettierignore" . ) > "$log" 2>&1 || true
  # prettier emite "[warn] <path>" para cada arquivo divergente. Segundo filtro
  # defensivo: mesmo se prettier nao honrar bem o --ignore-path, paths gerados
  # nao entram na contagem.
  local n
  n=$(grep -E '^\[warn\] [^[:space:]].*\.[mc]?[jt]sx?$' "$log" 2>/dev/null \
    | grep -vE '^\[warn\] (.*/)?(node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/' \
    | grep -vcE '\.(min|bundle|chunk)\.js$')
  printf '%d\n' "$(_num "${n:-0}")"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: SEMPRE o ruleset do QG, ignorando config do projeto
  # (--no-config-lookup + --config). Dev nao afrouxa regra no proprio repo.
  ( cd "$dir" && npx --yes eslint --no-config-lookup \
      --config "$rules/eslint.config.mjs" . ) > "$log" 2>&1 || true
  # eslint stylish output: linha "  N:N  error  msg  rule"; conta linhas com "error" precedidas de localizacao.
  _grep_count '^[[:space:]]+[0-9]+:[0-9]+[[:space:]]+error' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Sem TypeScript: usa node --check em cada .js. Se ha tsconfig.json: usa tsc
  # com o tsconfig.base.json do QG (strict travado), ignorando o do projeto.
  if [ -f "$dir/tsconfig.json" ] && command -v npx >/dev/null 2>&1; then
    # Tamper-resistance: o tsconfig do projeto-alvo NUNCA e lido. Geramos um
    # tsconfig EFEMERO dentro do dir-alvo que faz `extends` do tsconfig.base.json
    # do QG (strictness travada, vinda do QG -- o dev nao afrouxa) porem com
    # `include`/`rootDir` apontando para as fontes do projeto. O `extends`
    # carrega SO o config do QG; o tsconfig.json do projeto e ignorado porque
    # rodamos `tsc -p <efemero>`, nao `-p tsconfig.json`. O config base e
    # JSX/React-Native-capaz (jsx: react-jsx, moduleResolution: bundler), entao
    # arquivos .tsx validos NAO geram TS17004/TS6142 fantasma -- o numero de
    # build errors reflete erros de tipo reais, nao ausencia de --jsx.
    local base_ts qg_tsconfig
    qg_tsconfig="$rules/tsconfig.base.json"
    if [ ! -f "$qg_tsconfig" ]; then
      echo "::error::tsconfig.base.json do QG ausente em $rules -- instalacao do gate corrompida (reinstale: 'git clone <repo> ~/.quality-gate' (Linux/macOS))" >> "$log"
      printf '0\n'
      return
    fi
    base_ts=$(cd "$dir" && pwd)
    # Path absoluto do tsconfig do QG p/ o `extends` resolver fora do dir-alvo.
    local qg_tsconfig_abs qg_jsx_shim
    qg_tsconfig_abs=$(cd "$(dirname "$qg_tsconfig")" && pwd)/$(basename "$qg_tsconfig")
    # Shim ambiente de JSX do QG: declara JSX.IntrinsicElements permissivo SO
    # como fallback global. Se o projeto fornece @types/react no node_modules,
    # os tipos reais do React vencem. Impede TS7026/TS2875 fantasma quando o
    # projeto-alvo nao instalou tipos de React -- sem afrouxar strictness.
    qg_jsx_shim="$(dirname "$qg_tsconfig_abs")/qg-jsx-shim.d.ts"
    local eff_tsconfig="$base_ts/.qg-tsconfig.json"
    # Efemero: extends do QG + include amplo (todas as fontes TS/TSX do alvo,
    # menos node_modules/dist) + shim JSX + rootDir no alvo. Sem ler o config
    # do projeto. shim referenciado por path absoluto (vive no rules/ do QG).
    cat > "$eff_tsconfig" <<EOF
{
  "extends": "$qg_tsconfig_abs",
  "compilerOptions": { "rootDir": "." },
  "include": ["**/*.ts", "**/*.tsx", "$qg_jsx_shim"],
  "exclude": ["node_modules", "dist", "coverage", ".qg-tsconfig.json"]
}
EOF
    ( cd "$dir" && npx --yes -p typescript tsc -p .qg-tsconfig.json ) > "$log" 2>&1 || true
    # moduleResolution "bundler" exige TypeScript 5.0+. Se o projeto pinou um
    # tsc antigo (npx prioriza node_modules), ele cospe TS5023/TS5095/TS6046.
    # Fallback p/ resolution "node" (ainda strict, ainda JSX) -- sem afrouxar.
    if grep -qE 'error TS(5023|5095|6046):' "$log"; then
      cat > "$eff_tsconfig" <<EOF
{
  "extends": "$qg_tsconfig_abs",
  "compilerOptions": { "rootDir": ".", "moduleResolution": "node", "module": "ESNext" },
  "include": ["**/*.ts", "**/*.tsx", "$qg_jsx_shim"],
  "exclude": ["node_modules", "dist", "coverage", ".qg-tsconfig.json"]
}
EOF
      : > "$log"
      ( cd "$dir" && npx --yes -p typescript tsc -p .qg-tsconfig.json ) > "$log" 2>&1 || true
    fi
    rm -f "$eff_tsconfig"
    # tsc imprime "file.ts(linha,col): error TSXXXX:" -- conta linhas com "error TS".
    _grep_count 'error TS[0-9]+:' "$log"
    return
  fi
  local errors=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! ( cd "$dir" && node --check "$f" ) >> "$log" 2>&1; then
      errors=$((errors + 1))
    fi
  done < <(_qg_node_sources "$dir")
  printf '%d\n' "$errors"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  # Roda o script "test" do package.json se existir; senao node --test.
  if [ -f "$dir/package.json" ] && jq -e '.scripts.test' "$dir/package.json" >/dev/null 2>&1; then
    ( cd "$dir" && npm test --silent ) > "$log" 2>&1 || true
  else
    ( cd "$dir" && node --test ) > "$log" 2>&1 || true
  fi
  # node --test imprime resumo "ℹ fail N". Para output TAP de jest/vitest, "# fail N".
  # Tomamos o primeiro que aparecer.
  local n
  n=$(awk '
    /^[[:space:]]*ℹ fail / { print $3; exit }
    /^# fail / { print $3; exit }
    /^Tests:.*[0-9]+ failed/ { for (i=1; i<=NF; i++) if ($i == "failed,") print $(i-1); exit }
  ' "$log")
  n=$(_num "$n")
  printf '%d\n' "${n%.*}"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # LEI (docs/contract.md): mede CODIGO-FONTE. --config aponta para o
  # eslint.config.mjs do QG (cujo PRIMEIRO elemento e o `ignores` canonico,
  # ignore GLOBAL do flat config) + --rule sobrepoe so a regra complexity.
  # Sem --config, --no-config-lookup deixaria o eslint sem ignore canonico e
  # ele varreria build/dist (bundles minificados -> complexity inflado).
  ( cd "$dir" && npx --yes eslint --no-config-lookup \
      --config "$rules/eslint.config.mjs" \
      --rule '{"complexity":["error",15]}' . ) > "$log" 2>&1 || true
  _grep_count 'has a complexity of [0-9]+' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  local cov_dir
  cov_dir=$(dirname "$out")/coverage-tmp-$$
  ( cd "$dir" && npx --yes c8 --reports-dir="$cov_dir" --reporter=json-summary node --test ) >/dev/null 2>&1 || true
  local pct=0
  if [ -f "$cov_dir/coverage-summary.json" ]; then
    pct=$(jq -r '.total.lines.pct // 0' "$cov_dir/coverage-summary.json" 2>/dev/null || echo 0)
    cp "$cov_dir/coverage-summary.json" "$out" 2>/dev/null || true
  else
    printf '{"coverage_percent": 0}\n' > "$out"
  fi
  rm -rf "$cov_dir"
  # Bug 2: nunca retorna vazio/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}
