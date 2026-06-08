#!/usr/bin/env bash
# Measurement functions for the web gate (pure static HTML + CSS).
# Source this file from web/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.
#
# NOTE: this gate measures ONLY fmt + lint. The build, test,
# complexity and coverage metrics are OMITTED -- static HTML/CSS has no concept
# of build/test/complexity/coverage. Documented in docs/languages/web.md.
# (Just as Swift omits complexity -- the contract allows a documented omission.)

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

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. The target
# project's .stylelintrc / .htmlhintrc / .prettierrc are IGNORED. Override ONLY
# via the external env var QG_RULESET_DIR -- NEVER from .qg.yaml/a project file.
# The absolute base is captured at SOURCE-TIME (before any cd), robust to
# cwd changes and to being sourced with a relative path.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: web.
# Presence of *.html / *.css / *.scss at the root AND absence of package.json
# (if there is a package.json it is a nodejs project -> nodejs/qg.sh covers its HTML/CSS).
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/package.json" ] && return 1
  ls "$dir"/*.html  >/dev/null 2>&1 && return 0
  ls "$dir"/*.htm   >/dev/null 2>&1 && return 0
  ls "$dir"/*.css   >/dev/null 2>&1 && return 0
  ls "$dir"/*.scss  >/dev/null 2>&1 && return 0
  return 1
}

# web has no dependency manager -> symmetry no-op (contract Bug 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  return 0
}

# HTML/CSS/SCSS sources. LAW (docs/contract.md): measures SOURCE CODE -- excludes
# generated/vendored dirs via QG's CANONICAL ignore (same list as
# web/rules/.prettierignore), never the target project's config.
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
  # Tamper-resistance: QG's --config + --no-editorconfig (ignores the target
  # project's .prettierrc and .editorconfig). --ignore-path points at
  # QG's CANONICAL .prettierignore (NEVER the project's): LAW -- measures
  # SOURCE CODE, generated/vendored dirs stay out. Checks HTML+CSS+SCSS.
  ( cd "$dir" && npx --yes prettier --check \
      --config "$rules/.prettierrc.json" --no-editorconfig \
      --ignore-path "$rules/.prettierignore" \
      "**/*.{html,css,scss}" ) > "$log" 2>&1 || true
  # prettier emits "[warn] <path>" for each diverging file. A defensive
  # filter: even if prettier does not honor --ignore-path well, generated/
  # minified paths do not enter the count.
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

  # stylelint (CSS/SCSS) -- QG's ruleset, ignores the project's config.
  local css_files
  css_files=$(_qg_web_css "$dir")
  if [ -n "$css_files" ]; then
    # stylelint: --config points at an explicit file -> ignores the project's
    # .stylelintrc (stylelint has no --no-config-lookup; --config already overrides).
    # Passes the EXPLICIT source list (already filtered by _qg_web_css with the
    # canonical ignore) instead of a glob "**/*" -- LAW: never scan generated/
    # vendored dirs nor *.min.css.
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

  # htmlhint (HTML) -- QG's ruleset, ignores the project's .htmlhintrc.
  local html_files
  html_files=$(_qg_web_html "$dir")
  if [ -n "$html_files" ]; then
    # EXPLICIT list (already filtered by _qg_web_html with the canonical ignore)
    # instead of a glob "**/*.html" -- LAW: never scan generated/vendored dirs.
    ( cd "$dir" && printf '%s\n' "$html_files" \
        | xargs npx --yes htmlhint \
        --config "$rules/.htmlhintrc" ) > "$log.html" 2>&1 || true
    local h
    # htmlhint summary: "N errors in M files" / lines "L:C msg".
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
