#!/usr/bin/env bash
# Diff-scoped measurement for the Rust gate (issue 17).
#
# A PR quality gate must measure the code the PR changed, not recompile the
# world. On a large workspace with heavy/native crates, measuring every metric
# over `--workspace --all-targets` twice (PR head + baseline) costs tens of
# minutes regardless of diff size, OOMs the linker under coverage
# instrumentation, and lets a platform-specific example in an UNTOUCHED crate
# gate an unrelated PR.
#
# This resolves the set of workspace packages a diff actually affects:
#   changed packages + their in-workspace reverse-dependents
# The reverse closure is what still catches downstream breakage (change a
# signature in a base crate, its consumers stop compiling). Touching a crate
# everything depends on therefore still expands to (nearly) the whole
# workspace -- that is correct, not a bug: the win is in the common case.
#
# Source this file from rust/qg.sh.

# Workspace-root paths that can affect every crate: no scoping is sound.
_QG_RUST_FULL_RE='^Cargo\.lock$|^Cargo\.toml$|^rust-toolchain(\.toml)?$|^\.cargo/config(\.toml)?$|^build\.rs$'

# Emits "<pkg_name>\t<pkg_root_rel>" for every workspace member of <dir>.
_qg_rust_members() {
  local dir="$1"
  # `pwd -P` (physical): cargo emits canonical `manifest_path`s, so on macOS
  # where $TMPDIR lives under /var -> /private/var a logical pwd would fail the
  # prefix match and silently drop every member (falling back to __FULL__).
  ( cd "$dir" && cargo metadata --no-deps --format-version 1 --offline 2>/dev/null \
      || cargo metadata --no-deps --format-version 1 2>/dev/null ) \
    | jq -r --arg root "$(cd "$dir" && pwd -P)" '
        .packages[]
        | . as $p
        | ($p.manifest_path | sub("/Cargo\\.toml$"; "")) as $abs
        | ($abs | if startswith($root + "/") then .[($root | length) + 1:]
                  elif . == $root then "" else null end) as $rel
        | select($rel != null)
        | "\($p.name)\t\($rel)"
      ' 2>/dev/null
}

# Emits "<dep_name>\t<dependent_name>" for every workspace-internal edge,
# i.e. the REVERSE dependency graph restricted to workspace members.
_qg_rust_reverse_edges() {
  local dir="$1"
  ( cd "$dir" && cargo metadata --format-version 1 --offline 2>/dev/null \
      || cargo metadata --format-version 1 2>/dev/null ) \
    | jq -r '
        (.workspace_members | map({key: ., value: true}) | from_entries) as $ws
        | (.packages | map({key: .id, value: .name}) | from_entries) as $name
        | .resolve.nodes[]
        | select($ws[.id])
        | .id as $dependent
        | .deps[]
        | select($ws[.pkg])
        | "\($name[.pkg])\t\($name[$dependent])"
      ' 2>/dev/null
}

# qg_rust_scope <dir> <changed_files>
#   <changed_files>: newline-separated paths relative to <dir>.
# Prints the affected package names (one per line, sorted), or the literal
# __FULL__ when a workspace-root trigger means no narrowing is sound.
# Prints nothing when the diff touches no workspace member.
qg_rust_scope() {
  local dir="$1" changed="$2"
  local seeds
  seeds=$(qg_rust_changed_packages "$dir" "$changed") || return 1
  [ "$seeds" = "__FULL__" ] && { printf '__FULL__\n'; return 0; }
  [ -z "$seeds" ] && return 0
  qg_rust_expand "$dir" "$seeds"
}

# qg_rust_changed_packages <dir> <changed_files>
# The SEED set: packages the diff literally touched, before reverse-dep
# expansion. Kept separate because examples are built only for these.
qg_rust_changed_packages() {
  local dir="$1" changed="$2"

  if printf '%s\n' "$changed" | grep -qE "$_QG_RUST_FULL_RE"; then
    printf '__FULL__\n'
    return 0
  fi

  local members seeds=""
  members=$(_qg_rust_members "$dir")
  [ -z "$members" ] && { printf '__FULL__\n'; return 0; }

  # Longest-prefix match: a path belongs to the deepest member root containing
  # it, so a nested crate is not attributed to its parent.
  local f name root best best_len len
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    best=""; best_len=-1
    while IFS=$'\t' read -r name root; do
      [ -z "$name" ] && continue
      if [ -z "$root" ]; then
        len=0
      elif [ "${f#"$root"/}" != "$f" ]; then
        len=${#root}
      else
        continue
      fi
      if [ "$len" -gt "$best_len" ]; then best="$name"; best_len="$len"; fi
    done <<< "$members"
    [ -n "$best" ] && seeds+="$best"$'\n'
  done <<< "$changed"

  printf '%s' "$seeds" | sed '/^$/d' | sort -u
}

# qg_rust_expand <dir> <seed_packages>
# BFS over the reverse graph: the seeds + everything that depends on them,
# transitively, within the workspace. This is what still catches downstream
# breakage after an API change in a base crate.
qg_rust_expand() {
  local dir="$1" seeds="$2"
  local edges frontier acc next dep dependent
  edges=$(_qg_rust_reverse_edges "$dir")
  acc="$seeds"
  frontier="$seeds"
  while [ -n "$frontier" ]; do
    next=""
    while IFS=$'\t' read -r dep dependent; do
      [ -z "$dep" ] && continue
      if printf '%s\n' "$frontier" | grep -qxF "$dep"; then
        if ! printf '%s\n' "$acc" | grep -qxF "$dependent"; then
          next+="$dependent"$'\n'
        fi
      fi
    done <<< "$edges"
    next=$(printf '%s' "$next" | sed '/^$/d' | sort -u)
    [ -z "$next" ] && break
    acc=$(printf '%s\n%s\n' "$acc" "$next" | sed '/^$/d' | sort -u)
    frontier="$next"
  done

  printf '%s\n' "$acc" | sed '/^$/d' | sort -u
}

# qg_rust_intersect_scope <dir> <scope>
# Keeps only the packages that actually exist as members of <dir>. The baseline
# tree predates the PR, so a package the PR ADDS is absent there; passing it to
# `cargo -p` would be a hard error. An added package legitimately reads as
# base=0 -- it did not exist.
qg_rust_intersect_scope() {
  local dir="$1" scope="$2"
  [ "$scope" = "__FULL__" ] && { printf '__FULL__\n'; return 0; }
  local members
  members=$(_qg_rust_members "$dir" | cut -f1 | sort -u)
  [ -z "$members" ] && return 0
  printf '%s\n' "$scope" | sed '/^$/d' | sort -u | comm -12 - <(printf '%s\n' "$members")
}

# qg_rust_pkg_flags <scope> -> "--workspace" or "-p a -p b"
qg_rust_pkg_flags() {
  local scope="$1"
  [ "$scope" = "__FULL__" ] && { printf -- '--workspace\n'; return 0; }
  local out="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    out+="-p $p "
  done <<< "$scope"
  printf '%s\n' "${out% }"
}

# qg_rust_scope_hash <scope>
# Identity of a measured scope. MUST enter the base-metrics cache key: a cached
# full-workspace TSV silently reused by a narrowed run (or vice versa) turns
# pre-existing findings into a phantom `0 -> N` regression -- exactly the false
# positive this change exists to remove.
qg_rust_scope_hash() {
  local scope="$1"
  if [ "$scope" = "__FULL__" ]; then
    printf 'full\n'
  else
    printf '%s\n' "$scope" | sed '/^$/d' | sort -u | shasum | cut -c1-12
  fi
}

# qg_rust_scope_summary <scope> <changed_count> <total_members>
qg_rust_scope_summary() {
  local scope="$1" seeds="$2" total="$3"
  if [ "$scope" = "__FULL__" ]; then
    printf 'full workspace\n'
  else
    local n
    n=$(printf '%s\n' "$scope" | sed '/^$/d' | wc -l | tr -d ' ')
    printf '%s/%s packages (%s) -- %s changed +%s reverse-deps\n' \
      "$n" "$total" "$(printf '%s' "$scope" | sed '/^$/d' | tr '\n' ',' | sed 's/,$//; s/,/, /g')" \
      "$seeds" "$((n - seeds))"
  fi
}
