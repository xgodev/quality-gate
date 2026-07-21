# Quality Gate

Quality gate shared across projects. Runs **the same** locally and in CI: fails **only** when the PR worsens some metric relative to a chosen base ref. Pre-existing debt never blocks -- only worsening blocks.

It ships as **per-language Docker images** on GHCR. Nothing to clone, no toolchain to install -- the image carries both the gate and the language toolchain.

```bash
docker run --rm -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
```

## The images

Public on GHCR (no login needed). Multi-arch (`linux/amd64` + `linux/arm64`), except `swift` which is amd64-only -- see the note below the table:

| Image | Language detected by | Metrics |
|---|---|---|
| `ghcr.io/xgodev/quality-gate/rust:v1` | `Cargo.toml` | fmt, lint, build, test, complexity, coverage |
| `ghcr.io/xgodev/quality-gate/go:v1` | `go.mod` | fmt, lint, build, test, complexity, coverage |
| `ghcr.io/xgodev/quality-gate/python:v1` | `pyproject.toml`, `setup.py`, `requirements*.txt` | fmt, lint, build, test, complexity, coverage |
| `ghcr.io/xgodev/quality-gate/nodejs:v1` | `package.json` | fmt, lint, build, test, complexity, coverage |
| `ghcr.io/xgodev/quality-gate/java:v1` | `pom.xml` (Maven only) | fmt, lint, build, test, complexity, coverage |
| `ghcr.io/xgodev/quality-gate/kotlin:v1` | `build.gradle[.kts]` + Kotlin sources | fmt, lint, build, test, complexity, coverage |
| `ghcr.io/xgodev/quality-gate/swift:v1` | `Package.swift` | fmt, lint, build, test, coverage |
| `ghcr.io/xgodev/quality-gate/web:v1` | HTML/CSS with **no** `package.json` | fmt, lint |

A project with `package.json` -- **including React/Vue/Svelte/Angular** -- is a `nodejs` project, not `web`. `web` covers pure static HTML/CSS only. Swift omits `complexity`; web omits `build`/`test`/`complexity`/`coverage` (see [`docs/languages/`](docs/languages/)).

### Which tag to use

| Tag | Meaning |
|---|---|
| `:v1` | **Pin this.** Moving major -- gets patches and new languages, never a breaking change. |
| `:v1.2.3` | Exact release. Pin for byte-reproducible verdicts. |
| `:latest` | Tracks the newest release. Do not pin in CI. |

## Requirements for the mount

`/src` must be the checkout **with its `.git`** -- the baseline is produced with `git archive <base>`, so the base ref must exist locally:

```bash
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/go:v1 --base origin/main
```

In GitHub Actions that means `fetch-depth: 0`. If the base ref is missing, the gate exits `2` telling you to `git fetch`.

## Two modes

**Comparative** (`--base <ref>`) -- measures the base ref and the current state, fails only on a worsened metric. This is the PR mode.

**Absolute** (no `--base`) -- measures the current state once. Always exit `0`, unless `.qg.yaml` declares `absolute_thresholds` and one is violated. Use when there is no reference branch.

```bash
# comparative
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/python:v1 --base origin/main
# absolute
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/python:v1
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Passed (or bypassed, or absolute with no violation) |
| `1` | Regressed vs the base, or an absolute threshold violated |
| `2` | Tool/setup error (missing toolchain, unreachable base ref) -- **never** a code verdict |
| `3` | No supported language detected (dispatcher only) |

## Useful flags and env vars

```bash
--base <ref>        # comparative mode against this git ref
--format json       # machine-readable output (default: text table)
--detect            # print the detected language slug(s) and exit
--cov-margin <pp>   # coverage tolerance in percentage points (default 1.0)
--log-dir <path>    # where to write the per-metric tool logs
```

```bash
QG_BYPASS_REASON="incident hotfix"   # forces a pass, recorded in the output
QG_BASE_REF=origin/main              # same as --base
QG_RULESET_DIR=/custom/rules         # override the shipped ruleset (operator only)
```

## In CI

Reusable workflow:

```yaml
jobs:
  gate:
    uses: xgodev/quality-gate/.github/workflows/gate.yml@v1
    with:
      lang: rust
      base: origin/${{ github.base_ref || 'main' }}
```

Or the image directly, in any CI:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
- run: |
    docker run --rm -v "$PWD:/src" -w /src \
      ghcr.io/xgodev/quality-gate/go:v1 \
      --base "origin/${{ github.base_ref || 'main' }}" --format json
```

## Monorepos

A `.qg.yaml` at the root with a `projects:` block lists the sub-projects; the dispatcher runs one gate per declared project plus the root. The aggregate verdict is the worst one (precedence `2 > 1 > 3 > 0`), and `--format json` emits `{aggregate_verdict, results:[...]}`.

## Tamper-resistance

The gate **ships and enforces its own rulesets** (`<lang>/rules/`). The target project's quality configs (`.eslintrc`, `clippy.toml`, `.stylelintrc`, `ruff.toml`, `detekt.yml`, ...) are **ignored by default** -- otherwise a dev loosens a rule in their own repo and the gate becomes theater. The only override is `QG_RULESET_DIR`, supplied by whoever *runs* the gate, never read from a file in the repo under test.

Likewise, fmt/lint/complexity measure **source**, never generated output: a QG-owned ignore list (`node_modules/`, `dist/`, `build/`, `.next/`, `coverage/`, minified bundles, ...) always applies.

## Running the scripts without Docker

The images are the supported path. If you need the raw scripts, clone the repo and run the dispatcher -- you are then responsible for installing each language's toolchain (see [`docs/languages/`](docs/languages/)):

```bash
git clone https://github.com/xgodev/quality-gate.git
./quality-gate/qg --base origin/main   # from inside your project
./quality-gate/qg --detect
```

Detection is 100% shell, zero AI: `qg` calls `<lang>/qg.sh --detect` to discover the language(s) and runs the matching gate(s), forwarding all flags.

## Documentation

- [`docs/contract.md`](docs/contract.md) -- the contract common to every language (CLI, exit codes, output, bypass, `.qg.yaml`).
- [`docs/output-format.md`](docs/output-format.md) -- text and JSON output formats.
- [`docs/consume.md`](docs/consume.md) -- integrating the gate into a project.
- [`docs/languages/`](docs/languages/) -- per-language metrics, tools and troubleshooting.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) -- development and the release process.

### Platform note

Every image is multi-arch except **`swift`**, which is `linux/amd64` only: there is no prebuilt arm64 SwiftLint binary for Linux, and compiling it from source adds ~20 min to every release. On Apple Silicon, run that one emulated:

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/swift:v1 --base origin/main
```
