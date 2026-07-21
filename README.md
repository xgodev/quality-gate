# Quality Gate

Quality gate shared across projects. Runs **the same** locally and in CI: fails **only** when the PR worsens some metric relative to a chosen base ref. Pre-existing debt never blocks -- only worsening blocks.

It ships as **per-language Docker images** on GHCR. Nothing to clone, no toolchain to install -- the image carries both the gate and the language toolchain.

```bash
docker run --rm -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
```

## The images

Public on GHCR (no login needed), multi-arch (`linux/amd64` + `linux/arm64`):

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

## Run it on your machine

Same command for every language -- only the image name changes. Run it from the
root of the checkout:

```bash
docker run --rm -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/<lang>:v1 --base origin/main
```

Copy-paste per language:

```bash
# rust
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
# go
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/go:v1 --base origin/main
# python
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/python:v1 --base origin/main
# nodejs (also React/Vue/Svelte/Angular)
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/nodejs:v1 --base origin/main
# java
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/java:v1 --base origin/main
# kotlin
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/kotlin:v1 --base origin/main
# swift
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/swift:v1 --base origin/main
# web (static HTML/CSS, no package.json)
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/web:v1 --base origin/main
```

Not sure which one? Ask the gate -- `--detect` prints the language slug(s) and exits:

```bash
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/go:v1 --detect
```

Practical notes for local runs:

- Drop `--base` for absolute mode (measure the current state, no comparison).
- The base ref must exist locally -- `git fetch origin main` first if needed.
- Toolchain caches live inside the container and are lost on `--rm`. To reuse
  them across runs, mount a named volume, e.g. Go:
  `-v qg-go:/go/pkg/mod -v qg-gobuild:/root/.cache/go-build`, Rust:
  `-v qg-cargo:/usr/local/cargo/registry`.
- If Docker cannot write to the mount (SELinux hosts), use `-v "$PWD:/src:z"`.

## Requirements for the mount

`/src` must be the checkout **with its `.git`** -- the baseline is produced with `git archive <base>`, so the base ref must exist locally:

```bash
docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/go:v1 --base origin/main
```

In GitHub Actions that means `fetch-depth: 0`. If the base ref is missing, the gate exits `2` and the error quotes git's own message.

**git-lfs repos work without git-lfs.** The baseline extraction bypasses the repo's lfs filters, so LFS paths land in the baseline as pointer files and the run needs neither `git-lfs` in the image nor the blobs in your object store. It says so with a `::notice::`. Source is measured normally -- LFS carries binary payload, not code.

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
QG_ALLOW_SYSTEM_PACKAGES=1           # authorize .qg.yaml system_packages (operator only)
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

## Native build dependencies

The images carry the language toolchain, not any project's C libraries. When a
project's build links system libraries (audio, GUI, FFI/`*-sys` crates, …),
declare them in `.qg.yaml` and the gate installs them once, before it builds --
so the image stays lean and generic while the project owns its deps:

```yaml
system_packages:
  - libasound2-dev
  - libjack-jackd2-dev
```

**The project declares, the runner decides.** `.qg.yaml` belongs to the repo
under test, so the gate installs nothing unless whoever runs it opts in with
`QG_ALLOW_SYSTEM_PACKAGES=1` -- otherwise the declaration is a `::warning::`
and the run continues. Same boundary as `QG_RULESET_DIR`, and for the same
reason: an unchecked list would let a repo install arbitrary packages as root,
or shadow the pinned toolchain with a distro one.

```bash
docker run --rm -v "$PWD:/src" -w /src -e QG_ALLOW_SYSTEM_PACKAGES=1 \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
```

Installed with `apt-get install --no-install-recommends`, as root, once, before
any measurement -- never through `sudo`. Entries must be Debian package names
(`[a-z0-9][a-z0-9._+-]*`); anything else (an apt flag, a shell expression) is
exit `2`. A failed install is exit `2` too -- a tool error, never a code
verdict. Not root, or no `apt-get` (local macOS): `::warning::` and the host is
assumed to provide them.

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
