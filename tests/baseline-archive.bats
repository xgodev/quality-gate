#!/usr/bin/env bats
# lib/baseline-archive.sh -- the single implementation every <lang>/qg.sh uses
# to materialize the base ref. Two invariants:
#   1. a git-lfs repo extracts WITHOUT git-lfs installed (pointers, not blobs)
#   2. a failure reports git's OWN stderr, never a generic guess

bats_require_minimum_version 1.5.0

load 'helpers/setup'

LIB="$QG_REPO_ROOT/lib/baseline-archive.sh"

# Repo whose .gitattributes routes *.bin through an lfs filter that is NOT
# installed -- exactly what a checkout of an LFS repo looks like inside the
# gate image.
mk_lfs_repo() {
  local d
  d=$(qg_tmp_dir)
  git -C "$d" -c init.defaultBranch=main init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  git -C "$d" config filter.lfs.process 'qg-git-lfs-absent filter-process'
  git -C "$d" config filter.lfs.smudge 'qg-git-lfs-absent smudge -- %f'
  git -C "$d" config filter.lfs.clean 'qg-git-lfs-absent clean -- %f'
  git -C "$d" config filter.lfs.required true
  printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$d/.gitattributes"
  printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%064d\nsize 3\n' 1 > "$d/blob.bin"
  printf 'fn main() {}\n' > "$d/main.rs"
  git -C "$d" -c filter.lfs.process= -c filter.lfs.clean=cat -c filter.lfs.required=false add -A >/dev/null 2>&1
  git -C "$d" -c filter.lfs.process= -c filter.lfs.clean=cat -c filter.lfs.required=false commit -q -m init >/dev/null 2>&1
  echo "$d"
}

@test "baseline: git-lfs repo extracts with git-lfs absent (pointers kept)" {
  repo=$(mk_lfs_repo); out=$(qg_tmp_dir)
  cd "$repo"
  # Plain git archive is what used to run -- prove it really is broken here,
  # so the assertion below is about our bypass and not a no-op.
  run git archive HEAD
  [ "$status" -ne 0 ] || return 1

  run bash -c "source '$LIB' && qg_extract_base_archive HEAD '$out'"
  [ "$status" -eq 0 ] || return 1
  [ -f "$out/main.rs" ] || return 1
  grep -q 'git-lfs.github.com/spec/v1' "$out/blob.bin" || return 1
  cd / && rm -rf "$repo" "$out"
}

@test "baseline: git-lfs bypass is announced, never silent" {
  repo=$(mk_lfs_repo); out=$(qg_tmp_dir)
  cd "$repo"
  run bash -c "source '$LIB' && qg_extract_base_archive HEAD '$out' 2>&1"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"::notice::"* ]] || return 1
  [[ "$output" == *"git-lfs"* ]] || return 1
  cd / && rm -rf "$repo" "$out"
}

@test "baseline: a repo without lfs extracts and stays quiet" {
  repo=$(qg_make_git_repo); out=$(qg_tmp_dir)
  cd "$repo"
  printf 'x\n' > f.txt
  git add -A && git -c user.email=t@t -c user.name=t commit -q -m f
  run bash -c "source '$LIB' && qg_extract_base_archive HEAD '$out' 2>&1"
  [ "$status" -eq 0 ] || return 1
  [ -f "$out/f.txt" ] || return 1
  [[ "$output" != *"git-lfs"* ]] || return 1
  cd / && rm -rf "$repo" "$out"
}

@test "baseline: failure surfaces git's own stderr, not a generic guess" {
  repo=$(qg_make_git_repo); out=$(qg_tmp_dir)
  cd "$repo"
  run bash -c "source '$LIB' && qg_extract_base_archive no-such-ref '$out' 2>&1"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"::error::"* ]] || return 1
  [[ "$output" == *"no-such-ref"* ]] || return 1
  # git's own words, verbatim -- the whole point of the fix
  [[ "$output" == *"fatal:"* ]] || return 1
  cd / && rm -rf "$repo" "$out"
}
