#!/usr/bin/env bash
# Measurement functions for the Node.js.
# Source this file from nodejs/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.

_grep_count() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -cE "$pattern" "$file" 2>/dev/null | head -1)
  [ -z "$n" ] && n=0
  printf '%d\n' "${n:-0}"
}

# Ensures a number; anything non-numeric (empty, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. Config do
# target project (.eslintrc*, .prettierrc, tsconfig) is IGNORED. Override ONLY
# via env externa QG_RULESET_DIR (setada por quem RODA o gate / pipeline)
# -- NEVER read from .qg.yaml/a project file. Default = bundled rules/.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: nodejs.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/package.json" ]
}

# Bug 1: resolves the dependency closure before measuring build/test.
# A resolution failure = tool-error (return 1); the caller does exit 2.
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  # Only resolve if node_modules is absent OR a lockfile is newer than node_modules.
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

  # The lockfile is authoritative: a missing manager becomes a clear tool-error,
  # NEVER a fallback to another manager (incorrect resolution + misleading error).
  if [ -f "$dir/pnpm-lock.yaml" ]; then
    if ! command -v pnpm >/dev/null 2>&1; then
      echo "::error::pnpm-lock.yaml present but 'pnpm' not found on PATH -- install: 'npm i -g pnpm' (Linux) / 'brew install pnpm' (macOS) (the project lockfile requires pnpm; falling back to npm would produce an incorrect resolution)" >> "$log"
      return 1
    fi
    ( cd "$dir" && pnpm i --frozen-lockfile ) >> "$log" 2>&1 || return 1
  elif [ -f "$dir/yarn.lock" ]; then
    if ! command -v yarn >/dev/null 2>&1; then
      echo "::error::yarn.lock present but 'yarn' not found on PATH -- install: 'npm i -g yarn' (Linux) / 'brew install yarn' (macOS) (the project lockfile requires yarn; falling back to npm would produce an incorrect resolution)" >> "$log"
      return 1
    fi
    # Fix 3: .yarnrc.yml at the root = Yarn Berry (v2+) -> 'yarn install
    # --immutable' (Berry equivalent of --frozen-lockfile; Berry does NOT accept
    # --frozen-lockfile). Without .yarnrc.yml = Yarn classic (v1) ->
    # --frozen-lockfile. A missing yarn stays a tool-error (msg above).
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

# Glob of JS/TS sources to iterate with node --check.
# LAW (docs/contract.md): measures SOURCE CODE -- excludes generated/vendored
# dirs via QG's canonical ignore (same list as nodejs/rules/.prettierignore),
# never the target project's config.
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
  # Tamper-resistance: QG's --config + --no-editorconfig (ignores the target
  # project's .prettierrc and .editorconfig). --ignore-path points at QG's
  # CANONICAL .prettierignore (NEVER the project's): LAW -- measures
  # SOURCE CODE, generated/vendored dirs stay out.
  ( cd "$dir" && npx --yes prettier --check \
      --config "$rules/.prettierrc.json" --no-editorconfig \
      --ignore-path "$rules/.prettierignore" . ) > "$log" 2>&1 || true
  # prettier emits "[warn] <path>" for each diverging file. A second defensive
  # filter: even if prettier does not honor --ignore-path well, generated paths
  # do not enter the count.
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
  # Tamper-resistance: ALWAYS QG's ruleset, ignoring the project's config
  # (--no-config-lookup + --config). The dev does not loosen a rule in their own repo.
  ( cd "$dir" && npx --yes eslint --no-config-lookup \
      --config "$rules/eslint.config.mjs" . ) > "$log" 2>&1 || true
  # eslint stylish output: line "  N:N  error  msg  rule"; counts lines with "error" preceded by a location.
  _grep_count '^[[:space:]]+[0-9]+:[0-9]+[[:space:]]+error' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # No TypeScript: uses node --check on each .js. If there is a tsconfig.json: uses tsc
  # with QG's tsconfig.base.json (strict locked), ignoring the project's.
  if [ -f "$dir/tsconfig.json" ] && command -v npx >/dev/null 2>&1; then
    # Tamper-resistance: the target project's tsconfig is NEVER read. We generate
    # an EPHEMERAL tsconfig inside the target dir that `extends` QG's tsconfig.base.json
    # (strictness locked, coming from QG -- the dev does not loosen it) but with
    # `include`/`rootDir` pointing at the project's sources. The `extends`
    # loads ONLY QG's config; the project's tsconfig.json is ignored because
    # we run `tsc -p <ephemeral>`, not `-p tsconfig.json`. The base config is
    # JSX/React-Native-capable (jsx: react-jsx, moduleResolution: bundler), so
    # valid .tsx files do NOT produce phantom TS17004/TS6142 -- the build error
    # count reflects real type errors, not the absence of --jsx.
    local base_ts qg_tsconfig
    qg_tsconfig="$rules/tsconfig.base.json"
    if [ ! -f "$qg_tsconfig" ]; then
      echo "::error::QG tsconfig.base.json absent in $rules -- corrupted gate install (reinstall: 'git clone <repo> ~/.quality-gate' (Linux/macOS))" >> "$log"
      printf '0\n'
      return
    fi
    base_ts=$(cd "$dir" && pwd)
    # Absolute path of QG's tsconfig so `extends` resolves outside the target dir.
    local qg_tsconfig_abs qg_jsx_shim
    qg_tsconfig_abs=$(cd "$(dirname "$qg_tsconfig")" && pwd)/$(basename "$qg_tsconfig")
    # QG's ambient JSX shim: declares a permissive JSX.IntrinsicElements ONLY
    # as a global fallback. If the project provides @types/react in node_modules,
    # React's real types win. Prevents phantom TS7026/TS2875 when the target
    # project did not install React types -- without loosening strictness.
    qg_jsx_shim="$(dirname "$qg_tsconfig_abs")/qg-jsx-shim.d.ts"
    local eff_tsconfig="$base_ts/.qg-tsconfig.json"
    # Ephemeral: QG's extends + a broad include (all of the target's TS/TSX
    # sources, minus node_modules/dist) + JSX shim + rootDir at the target.
    # Without reading the project's config. The shim is referenced by absolute
    # path (it lives in QG's rules/).
    cat > "$eff_tsconfig" <<EOF
{
  "extends": "$qg_tsconfig_abs",
  "compilerOptions": { "rootDir": "." },
  "include": ["**/*.ts", "**/*.tsx", "$qg_jsx_shim"],
  "exclude": ["node_modules", "dist", "coverage", ".qg-tsconfig.json"]
}
EOF
    ( cd "$dir" && npx --yes -p typescript tsc -p .qg-tsconfig.json ) > "$log" 2>&1 || true
    # moduleResolution "bundler" requires TypeScript 5.0+. If the project pinned
    # an old tsc (npx prioritizes node_modules), it spits TS5023/TS5095/TS6046.
    # Fallback to resolution "node" (still strict, still JSX) -- without loosening.
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
    # tsc prints "file.ts(line,col): error TSXXXX:" -- counts lines with "error TS".
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
  # Runs the package.json "test" script if it exists; otherwise node --test.
  if [ -f "$dir/package.json" ] && jq -e '.scripts.test' "$dir/package.json" >/dev/null 2>&1; then
    ( cd "$dir" && npm test --silent ) > "$log" 2>&1 || true
  else
    ( cd "$dir" && node --test ) > "$log" 2>&1 || true
  fi
  # node --test prints a "ℹ fail N" summary. For jest/vitest TAP output, "# fail N".
  # We take the first one that appears.
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
  # Bug 2: never returns empty/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}
# Baseline submodule extraction (shared logic across all language gates).
# `git archive` does NOT expand git submodules: in the baseline checkout the
# submodule dirs are empty, so a submodule-dependent build fails, the base
# metrics are undercounted, and every PR is reported as a false `regressed`
# (issue #2). This walks the submodules registered in <treeish> and, for each
# one, extracts the exact commit it is pinned to into the baseline tree, using
# the working tree's already-initialized submodule object store. Recurses into
# nested submodules. No-op for repos without a .gitmodules. Never aborts the
# gate: an un-extractable submodule yields a ::warning:: and is skipped.
_qg_extract_submodules() {
  local gitdir="$1" treeish="$2" dest="$3" wt="$4"
  local list
  list=$(git --git-dir="$gitdir" config --blob "$treeish:.gitmodules" \
           --get-regexp '^submodule\..*\.path$' 2>/dev/null) || return 0
  local key path sha subdir
  while read -r key path; do
    [ -z "$path" ] && continue
    sha=$(git --git-dir="$gitdir" rev-parse "$treeish:$path" 2>/dev/null) || continue
    subdir=$(git -C "$wt/$path" rev-parse --absolute-git-dir 2>/dev/null) || {
      echo "::warning::baseline: submodule '$path' is not initialized in the working tree -- base build may undercount; run 'git submodule update --init --recursive'" >&2
      continue
    }
    mkdir -p "$dest/$path"
    if git --git-dir="$subdir" archive "$sha" 2>/dev/null | tar -xC "$dest/$path"; then
      _qg_extract_submodules "$subdir" "$sha" "$dest/$path" "$wt/$path"
    else
      echo "::warning::baseline: failed to extract submodule '$path' at $sha -- base build may undercount" >&2
    fi
  done <<< "$list"
}
