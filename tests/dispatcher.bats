#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/setup'

# Creates a fake ROOT with controllable synthetic gates. Each fake gate:
#  --detect : exit 0 + prints slug if <sentinel> exists in cwd, otherwise exit 1
#  (without --detect): prints minimal JSON and exits with the code stored in
#                  $FAKE_<SLUG>_EXIT (default 0); echoes the received args.
make_fake_root() {
  local root="$1"; shift
  mkdir -p "$root"
  cp "$QG_REPO_ROOT/qg" "$root/qg"
  chmod +x "$root/qg"
  while [ $# -gt 0 ]; do
    local slug="$1" sentinel="$2" exitcode="$3"
    shift 3
    mkdir -p "$root/$slug"
    cat > "$root/$slug/qg.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
SLUG="$slug"
SENT="$sentinel"
RC=$exitcode
for a in "\$@"; do
  if [ "\$a" = "--detect" ]; then
    if [ -f "./\$SENT" ]; then echo "\$SLUG"; exit 0; fi
    exit 1
  fi
done
echo "{\"schema_version\":\"1.1\",\"mode\":\"comparative\",\"language\":\"\$SLUG\",\"branch\":\"x\",\"base_ref\":\"origin/main\",\"started_at\":\"2026-05-15T10:00:00Z\",\"duration_seconds\":1,\"verdict\":\"passed\",\"bypass_reason\":null,\"metrics\":[]}"
exit \$RC
EOF
    chmod +x "$root/$slug/qg.sh"
  done
}

setup() {
  qg_clean_env
}

@test "dispatcher: 0 matches -> exit 3 + message" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 0
  cd "$proj"
  run "$root/qg" --base origin/main
  [ "$status" -eq 3 ]
  [[ "$output" == *"no supported language detected"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: 1 match -> forwards the gate's exit code" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 1 nodejs NODE_SENTINEL 0
  cd "$proj"
  touch GO_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 1 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: 1 match exit 0 -> exit 0" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  cd "$proj"; touch GO_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 0 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches -> runs all, aggregate verdict = worst (1 beats 0)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 1
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 1 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches -> precedence 2 > 1 (tool error beats regression)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 1 nodejs NODE_SENTINEL 2
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --base origin/main
  [ "$status" -eq 2 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches --format json -> enveloped array with aggregate_verdict" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 1
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --base origin/main --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.aggregate_verdict == "regressed"'
  echo "$output" | jq -e '.results | length == 2'
  echo "$output" | jq -e '.schema_version == "1.1"'
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: --detect lists detected slugs, exit 0" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 0
  cd "$proj"; touch GO_SENTINEL NODE_SENTINEL
  run "$root/qg" --detect
  [ "$status" -eq 0 ]
  [[ "$output" == *"go"* ]]
  [[ "$output" == *"nodejs"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: --detect with no matches -> exit 3" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  cd "$proj"
  run "$root/qg" --detect
  [ "$status" -eq 3 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: .qg.yaml projects: uses ONLY the list (monorepo)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0 nodejs NODE_SENTINEL 1
  mkdir -p "$proj/backend" "$proj/frontend"
  touch "$proj/backend/GO_SENTINEL" "$proj/frontend/NODE_SENTINEL"
  # root without a sentinel; only projects: should be considered
  cat > "$proj/.qg.yaml" <<EOF
projects:
  - path: backend
    lang: go
  - path: frontend
EOF
  cd "$proj"
  run "$root/qg" --base origin/main --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.results | length == 2'
  echo "$output" | jq -e '[.results[].language] | sort == ["go","nodejs"]'
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: .qg.yaml projects: unknown key -> exit 2" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  cat > "$proj/.qg.yaml" <<EOF
projects:
  - path: backend
    bogus: value
EOF
  cd "$proj"
  run "$root/qg" --base origin/main
  [ "$status" -eq 2 ]
  [[ "$output" == *".qg.yaml"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher (real ROOT): pure Java + build.gradle.kts -> only 'java'" {
  local proj
  proj=$(qg_tmp_dir)
  mkdir -p "$proj/src/main/java"
  echo "plugins { java }" > "$proj/build.gradle.kts"
  echo "public class Foo {}" > "$proj/src/main/java/Foo.java"
  cd "$proj"
  run "$QG_REPO_ROOT/qg" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "java" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$proj"
}

@test "dispatcher (real ROOT): pure Kotlin + build.gradle.kts -> only 'kotlin'" {
  local proj
  proj=$(qg_tmp_dir)
  mkdir -p "$proj/src/main/kotlin"
  echo "plugins { kotlin(\"jvm\") }" > "$proj/build.gradle.kts"
  echo "fun main() {}" > "$proj/src/main/kotlin/Main.kt"
  cd "$proj"
  run "$QG_REPO_ROOT/qg" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "kotlin" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$proj"
}

@test "dispatcher (real ROOT): pure Java + build.gradle (Groovy) -> only 'java'" {
  local proj
  proj=$(qg_tmp_dir)
  mkdir -p "$proj/src/main/java"
  : > "$proj/build.gradle"
  echo "public class Foo {}" > "$proj/src/main/java/Foo.java"
  cd "$proj"
  run "$QG_REPO_ROOT/qg" --detect
  [ "$status" -eq 0 ]
  [ "$output" = "java" ]
  cd "$QG_REPO_ROOT"
  rm -rf "$proj"
}

@test "dispatcher (real ROOT): mixed Java + Kotlin Gradle project -> both 'java' and 'kotlin'" {
  local proj
  proj=$(qg_tmp_dir)
  mkdir -p "$proj/src/main/java" "$proj/src/main/kotlin"
  echo "plugins { java; kotlin(\"jvm\") }" > "$proj/build.gradle.kts"
  echo "public class Foo {}" > "$proj/src/main/java/Foo.java"
  echo "fun bar() {}" > "$proj/src/main/kotlin/Bar.kt"
  cd "$proj"
  run "$QG_REPO_ROOT/qg" --detect
  [ "$status" -eq 0 ]
  [[ "$output" == *"java"* ]]
  [[ "$output" == *"kotlin"* ]]
  cd "$QG_REPO_ROOT"
  rm -rf "$proj"
}

@test "dispatcher: forwards --base and --format intact to the gate" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  mkdir -p "$root/go"
  cp "$QG_REPO_ROOT/qg" "$root/qg"; chmod +x "$root/qg"
  cat > "$root/go/qg.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
for a in "$@"; do [ "$a" = "--detect" ] && { [ -f ./GO_SENTINEL ] && { echo go; exit 0; }; exit 1; }; done
echo "ARGS: $*" >&2
echo '{"schema_version":"1.1","mode":"comparative","language":"go","branch":"x","base_ref":"origin/develop","started_at":"2026-05-15T10:00:00Z","duration_seconds":1,"verdict":"passed","bypass_reason":null,"metrics":[]}'
exit 0
EOF
  chmod +x "$root/go/qg.sh"
  cd "$proj"; touch GO_SENTINEL
  run --separate-stderr "$root/qg" --base origin/develop --format json
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"--base origin/develop"* ]]
  [[ "$stderr" == *"--format json"* ]]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: N matches --format json -- a silent tool-error gate does not corrupt the envelope" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  # A gate that detects but emits NOTHING on stdout and exits 2 (tool error
  # before render_json) -- the aggregate JSON must stay valid.
  mkdir -p "$root/rust"
  cat > "$root/rust/qg.sh" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--detect" ]; then
    [ -f ./RUST_SENTINEL ] && { echo rust; exit 0; }
    exit 1
  fi
done
echo "::error::tool missing" >&2
exit 2
EOS
  chmod +x "$root/rust/qg.sh"
  cd "$proj"; touch GO_SENTINEL RUST_SENTINEL
  run --separate-stderr "$root/qg" --base origin/main --format json
  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e . >/dev/null
  printf '%s' "$output" | jq -e '.aggregate_verdict == "failed"' >/dev/null
  printf '%s' "$output" | jq -e '.results | length == 2' >/dev/null
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}

@test "dispatcher: 0 matches -- hygiene still runs (violation beats exit 3)" {
  local root proj
  root=$(qg_tmp_dir); proj=$(qg_tmp_dir)
  make_fake_root "$root" go GO_SENTINEL 0
  mkdir -p "$root/hygiene"
  cp "$QG_REPO_ROOT/hygiene/scan.sh" "$root/hygiene/scan.sh"
  mkdir -p "$proj/.github/workflows"
  printf 'on:\n  pull_request:\njobs:\n  t:\n    steps:\n      - run: pytest || true\n' > "$proj/.github/workflows/ci.yml"
  cd "$proj"
  run "$root/qg" --base origin/main
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q '|| true'
  rm -rf "$proj/.github"
  run "$root/qg" --base origin/main
  [ "$status" -eq 3 ]
  cd "$QG_REPO_ROOT"; rm -rf "$root" "$proj"
}
