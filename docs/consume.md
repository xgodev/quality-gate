# How to use Quality Gate in your project

This guide covers **local** use (dev on the machine). CI will be documented in V2.

## Prerequisites

1. Git, bash 4+, awk, tar (system).
2. Language-specific prereqs for your project. See [`languages/`](languages/).

For Rust: cargo, cargo-llvm-cov, jq.

## Setup (once per machine)

```bash
git clone git@github.com:xgodev/quality-gate.git ~/.quality-gate
```

Update when the platform team announces changes:

```bash
git -C ~/.quality-gate pull --ff-only
```

## Run manually

In your project directory:

```bash
~/.quality-gate/rust/qg.sh --base origin/main
```

Or by setting env vars:

```bash
QG_BASE_REF=origin/main ~/.quality-gate/rust/qg.sh
```

### Common options

```bash
# Different coverage tolerance (default 1.0pp)
~/.quality-gate/rust/qg.sh --base origin/main --cov-margin 0.5

# Re-extract baseline (ignore cache)
~/.quality-gate/rust/qg.sh --base origin/main --refresh-baseline

# Force full gate (skip fast-path)
~/.quality-gate/rust/qg.sh --base origin/main --force-full

# JSON output for parsing
~/.quality-gate/rust/qg.sh --base origin/main --format json > result.json
```

## Git pre-push hook (optional)

Add to `.git/hooks/pre-push`:

```bash
#!/usr/bin/env bash
exec ~/.quality-gate/rust/qg.sh --base origin/main
```

```bash
chmod +x .git/hooks/pre-push
```

## Per-repo config (`.qg.yaml` optional)

At your project root:

```yaml
cov_margin: 2.0
skip_metrics:
  - metric: complexity
    reason: "legacy module, refactor plan in INT-1234"
    until: "2026-09-01"
extra_fast_path_paths:
  - "^vendor/"
```

Full rules: [`contract.md`](contract.md#per-repo-config-qgyaml-optional).

## Emergency bypass

Production hotfix at 3am, broken baseline, etc.:

```bash
QG_BYPASS_REASON="INT-9999 hotfix prod down, corrupted baseline" \
  ~/.quality-gate/rust/qg.sh --base origin/main
```

The bypass is recorded in `target/qg-logs/bypass.log`. Use with discretion.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `::error::--base is required` | Did not pass a base ref | Add `--base origin/main` |
| `::error::cargo-llvm-cov not found` | Missing prereq | `cargo install cargo-llvm-cov` |
| Red gate on a PR that did not touch Rust | Fast-path did not trigger | Check whether some `Cargo.*` or `.rs` was modified |
| Stale baseline cache | Divergent cache (when the gate's own staleness check is bypassed via `--baseline-dir`) | `--refresh-baseline` or `rm -rf /tmp/qg-baseline-*`. For default-cache runs, staleness is detected automatically via the `.qg-baseline-prepared` sentinel. |
| `git archive` failed | Ref does not exist locally | `git fetch origin` |
| `::warning::baseline: submodule '<x>' is not initialized` | A submodule the build needs is absent from the working tree, so it cannot be extracted into the baseline | `git submodule update --init --recursive`, then re-run (or `--refresh-baseline`) |

Per-language details in [`languages/<lang>.md`](languages/).

## Smoke test (manual validation)

To confirm the installation works end-to-end:

```bash
# Clone the gate
git clone git@github.com:xgodev/quality-gate.git ~/.quality-gate

# Test 1: baseline against itself -> should exit 0 (passed)
cd ~/.quality-gate/rust/test-fixtures/baseline
~/.quality-gate/rust/qg.sh \
  --base origin/main \
  --baseline-dir "$(pwd)" \
  --force-full
echo "Expected: exit 0"

# Test 2: regressed against baseline -> should exit 1 (regressed)
cd ~/.quality-gate/rust/test-fixtures/regressed
~/.quality-gate/rust/qg.sh \
  --base origin/main \
  --baseline-dir ~/.quality-gate/rust/test-fixtures/baseline \
  --force-full
echo "Expected: exit 1, 5 regressed metrics"

# Test 3: governed bypass -> should exit 0 with a warning
QG_BYPASS_REASON="smoke test" ~/.quality-gate/rust/qg.sh \
  --base origin/main \
  --baseline-dir ~/.quality-gate/rust/test-fixtures/baseline \
  --force-full
echo "Expected: exit 0, ::warning:: visible, audit log written"
```

If the 3 tests exit with the expected exit codes, the installation is OK.
