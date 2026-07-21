#!/usr/bin/env bash
# QG_CONTRACT_VERSION=1
#
# lib/baseline-archive.sh -- the ONE implementation of "materialize the base
# ref into a directory". Every <lang>/qg.sh sources this; the extraction must
# behave identically across languages, so it lives here and nowhere else.
#
# Two things it does that a bare `git archive` does not:
#
#  * git-lfs filters are neutralized. `git archive` runs the repo's configured
#    filters, so on an LFS repo it needs `git-lfs` on PATH and the blobs in the
#    local object store -- inside the gate image it has neither, and the whole
#    run dies with "the remote end hung up unexpectedly". The baseline exists to
#    be measured (fmt/lint/build/test on SOURCE), and LFS content is binary
#    payload, never source, so the pointer files are the right baseline: fast,
#    offline, deterministic. The bypass is ANNOUNCED (::notice::), never silent.
#
#  * a failure reports git's OWN stderr. The previous `2>/dev/null` turned every
#    cause (missing git-lfs, permissions, corrupt object) into the same generic
#    "try git fetch origin", which sent readers chasing the wrong problem.

# Extracts <ref> into <target> (which must already exist).
# Returns 0 on success; on failure prints ::error:: with git's own message.
qg_extract_base_archive() {
  local ref="$1" target="$2"
  local errfile rc

  if git grep -qI 'filter=lfs' "$ref" -- '*.gitattributes' 2>/dev/null; then
    echo "::notice::baseline: git-lfs filters bypassed -- LFS paths are extracted as pointer files (binary payload is not measured)" >&2
  fi

  errfile=$(mktemp -t qg-archive-err-XXXXXX)
  git -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.clean= \
      -c filter.lfs.required=false \
      archive "$ref" 2>"$errfile" | tar -xC "$target"
  rc=${PIPESTATUS[0]}

  if [ "$rc" -ne 0 ]; then
    local detail
    detail=$(grep -v '^$' "$errfile" | head -3 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    rm -f "$errfile"
    echo "::error::failed to extract '$ref' via git archive: ${detail:-no output from git} -- the ref must exist locally (try 'git fetch origin')" >&2
    return 1
  fi
  rm -f "$errfile"
  return 0
}
