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
```

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
