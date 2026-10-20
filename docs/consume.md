# How to use Quality Gate in your project

This guide covers **local** use (dev on the machine). For CI, see the
[`README`](../README.md#in-ci) -- the reusable `gate.yml` workflow or the image
straight from any runner.

## Prerequisites

Nothing, if you run the Docker image: it carries the gate AND the language
toolchain. Just Docker and a git checkout with history (`fetch-depth: 0` in CI
-- the gate needs the base ref).

Running the scripts from a clone instead means you own the prereqs: git,
bash 4+, awk, tar, jq, plus the language's tools (for Rust: cargo,
cargo-llvm-cov). See [`languages/`](languages/).

## Run manually

From the root of your checkout -- only the image name changes per language:

```bash
docker run --rm -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
```

Or by setting env vars:

```bash
docker run --rm -v "$PWD:/src" -w /src -e QG_BASE_REF=origin/main \
  ghcr.io/xgodev/quality-gate/rust:v1
```

The examples below use `qg` as a stand-in for that `docker run` prefix:

```bash
qg() { docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/rust:v1 "$@"; }
```

### Common options

```bash
# Fast pre-PR run: defers coverage + complexity (reported as skipped). Never in CI.
qg --base origin/main --quick

# Different coverage tolerance (default 1.0pp)
qg --base origin/main --cov-margin 0.5

# Re-extract baseline (ignore cache)
qg --base origin/main --refresh-baseline

# Force full gate (skip fast-path)
qg --base origin/main --force-full

# JSON output for parsing
qg --base origin/main --format json > result.json

# Measure baseline and PR one after the other (default: concurrent from 4 cores)
qg --base origin/main --no-parallel
```

## Keep the toolchain cache warm (containerized runs)

`docker run --rm` throws the container away, and with it everything the build
downloaded and compiled: a fresh image resolves dependencies from scratch on
every run, which is most of the wall-clock on the first measurement of each
side. Mount a **named volume** for the toolchain's cache and the gate reuses it
across runs, exactly as it would on a developer machine. The project mount
(`-v "$PWD:/src"`) stays as it is -- only cache paths are added.

```bash
# Rust: crates registry + a persistent target dir (the gate gives each side its
# own subdir under it, so base and PR never share artifacts)
docker run --rm -v "$PWD:/src" -w /src \
  -v qg-cargo-registry:/usr/local/cargo/registry \
  -v qg-rust-target:/qg-cache/target -e CARGO_TARGET_DIR=/qg-cache/target \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main

# Go: module cache + build cache
docker run --rm -v "$PWD:/src" -w /src \
  -v qg-go:/qg-cache -e GOMODCACHE=/qg-cache/mod -e GOCACHE=/qg-cache/build \
  ghcr.io/xgodev/quality-gate/go:v1 --base origin/main
```

Same idea for the others -- one volume, one env var:

| Language | Mount | Env var |
|---|---|---|
| rust | `-v qg-cargo-registry:/usr/local/cargo/registry` + `-v qg-rust-target:/qg-cache/target` | `CARGO_TARGET_DIR=/qg-cache/target` |
| go | `-v qg-go:/qg-cache` | `GOMODCACHE=/qg-cache/mod`, `GOCACHE=/qg-cache/build` |
| java | `-v qg-m2:/qg-cache/m2` | `MAVEN_OPTS=-Dmaven.repo.local=/qg-cache/m2` |
| kotlin | `-v qg-gradle:/qg-cache/gradle` | `GRADLE_USER_HOME=/qg-cache/gradle` |
| nodejs, web | `-v qg-npm:/qg-cache/npm` | `npm_config_cache=/qg-cache/npm` |
| python | `-v qg-pip:/qg-cache/pip` | `PIP_CACHE_DIR=/qg-cache/pip` |
| swift | `-v qg-swiftpm:/root/.cache/org.swift.swiftpm` | -- (SwiftPM has no cache env var; mount its default path) |

Two warnings. The cache is **build input, never measurement input**: it only
changes how long a tool takes, never what it reports, and the gate keeps
enforcing its own rulesets regardless. And a volume shared by two gate runs at
once is a lock fight -- give each concurrent job its own volume name (in CI,
prefer the runner's own cache action over a volume).

## Local git pre-push hook (optional, your choice)

Add to `.git/hooks/pre-push`:

```bash
#!/usr/bin/env bash
exec docker run --rm -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main --quick
```

```bash
chmod +x .git/hooks/pre-push
```

`--quick` keeps the hook fast enough that you do not start skipping it; CI runs
the full gate on the PR.

## Per-repo config (`.qg.yaml` optional)

At your project root:

```yaml
cov_margin: 2.0
extra_fast_path_paths:
  - "^vendor/"
```

Note what a project file can **not** do: it cannot point the gate at your own
lint/format config, and it cannot drop a metric. The gate ships and enforces
its own rulesets -- otherwise it is theater. Full rules:
[`contract.md`](contract.md).

## Emergency bypass

Production hotfix at 3am, broken baseline, etc.:

```bash
docker run --rm -v "$PWD:/src" -w /src \
  -e QG_BYPASS_REASON="hotfix prod down, corrupted baseline" \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
```

The bypass is recorded in `target/qg-logs/bypass.log`. Use with discretion.

A slow gate is the usual reason people reach for the bypass -- try `--quick`
first: it measures less, but it measures it for real.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `::error::cargo-llvm-cov not found` | Running from a clone without the prereq | `cargo install cargo-llvm-cov`, or use the Docker image |
| Green gate on a PR that did not touch Rust | Fast-path triggered (by design) | Nothing: no Rust changed. `--force-full` measures anyway |
| `complexity`/`coverage` reported as `skipped` | The run used `--quick`/`QG_QUICK=1` | Drop `--quick` for a complete run |
| Both sides seem to run at once and the machine swaps | Parallel sides on a small or memory-tight machine | `--no-parallel` (or `QG_PARALLEL=0`) |
| `::error::the PR measurement died` | A side was killed -- usually OOM | Re-run with `--no-parallel`; it is a tool-error (exit 2), not a regression |
| Stale baseline cache | Divergent cache (when the gate's own staleness check is bypassed via `--baseline-dir`) | `--refresh-baseline` or `rm -rf /tmp/qg-baseline-*`. For default-cache runs the baseline dir is keyed by project and base SHA, so a new base automatically gets a fresh extraction. |
| `git archive` failed | The `::error::` quotes git's own message -- read it. Usually the ref does not exist locally | `git fetch origin` |
| `::notice::baseline: git-lfs filters bypassed` | The repo tracks paths through git-lfs | Nothing to do: LFS paths are measured as pointer files, source is unaffected |
| `::warning::baseline: submodule '<x>' is not initialized` | A submodule the build needs is absent from the working tree, so it cannot be extracted into the baseline | `git submodule update --init --recursive`, then re-run (or `--refresh-baseline`) |

Per-language details in [`languages/<lang>.md`](languages/).

## Smoke test (manual validation)

To confirm an installation works end-to-end, run the gate against this repo's
own Rust fixtures (clone of this repo):

```bash
git clone git@github.com:xgodev/quality-gate.git /tmp/quality-gate
QG=/tmp/quality-gate

# Test 1: baseline against itself -> should exit 0 (passed)
cd "$QG/rust/test-fixtures/baseline"
"$QG/rust/qg.sh" --base origin/main --baseline-dir "$(pwd)" --force-full
echo "Expected: exit 0"

# Test 2: regressed against baseline -> should exit 1 (regressed)
cd "$QG/rust/test-fixtures/regressed"
"$QG/rust/qg.sh" \
  --base origin/main \
  --baseline-dir "$QG/rust/test-fixtures/baseline" \
  --force-full
echo "Expected: exit 1, regressed metrics"

# Test 3: governed bypass -> should exit 0 with a warning
QG_BYPASS_REASON="smoke test" "$QG/rust/qg.sh" \
  --base origin/main \
  --baseline-dir "$QG/rust/test-fixtures/baseline" \
  --force-full
echo "Expected: exit 0, ::warning:: visible, audit log written"

# Test 4: quick mode -> exit 0, complexity + coverage reported as skipped
cd "$QG/rust/test-fixtures/baseline"
"$QG/rust/qg.sh" --base origin/main --baseline-dir "$(pwd)" --force-full --quick
echo "Expected: exit 0, 'skipped (quick)' rows, ::warning:: about deferred metrics"
```

If the tests exit with the expected exit codes, the installation is OK.
