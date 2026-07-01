# Quality Gate

Quality gate shared across projects. Runs **the same** locally and in CI: fails **only** when the PR worsens some metric relative to a chosen base ref.

This repository is **two-in-one**:

- **CLI/CI:** clone the repo and run the dispatcher `./qg` (or `<lang>/qg.sh`) directly -- `.claude-plugin/` is inert outside Claude Code.
- **Claude Code plugin:** installs the `quality-gate` skill **together** with the scripts (bundled dispatcher, no runtime clone):

```text
/plugin marketplace add git@github.com:xgodev/quality-gate.git
/plugin install quality-gate@xgodev-quality-gate
```

The marketplace is named `xgodev-quality-gate` (scoped to this repo, to avoid colliding with other `xgodev/*` marketplaces); the plugin inside it is `quality-gate`. Another plugin can declare `quality-gate@xgodev-quality-gate` as a dependency, re-listing this repo in its own `marketplace.json`.

## How it works

1. Each supported language has a standalone script at `<lang>/qg.sh` (e.g. `rust/qg.sh`).
2. The script compares metrics (fmt, lint, build, test, complexity, coverage) between the current state and the base ref passed via `--base`.
3. Pre-existing debt never blocks. Only worsening blocks.

### Dispatcher `qg` (entry point)

The canonical way to run is the **`qg` dispatcher at the root**:

```bash
cd /path/to/your/project
~/.quality-gate/qg --base origin/main          # run the gate(s)
~/.quality-gate/qg --detect                    # list languages
```

100% shell detection (zero AI): `qg` calls `<lang>/qg.sh --detect` to
discover the language(s) and run the matching gate(s). It forwards
all flags. **Monorepo:** a `.qg.yaml` with a `projects:` block lists the
sub-projects. Exit codes: `0` green, `1` regression/threshold, `2`
tool/setup, **`3` no supported language detected** (dispatcher-exclusive).
Aggregate verdict of N gates = worst (precedence `2 > 1 > 3 > 0`);
with `--format json` it emits `{aggregate_verdict, results:[...]}`.

### Absolute mode and `--detect` (contract v1.1)

- **`--detect`**: `<lang>/qg.sh --detect` prints the language slug + exit 0 if the sentinel exists at the project root, or exit 1 if not. Short-circuits everything. The dispatcher uses this to discover which gates to run without a hardcoded table.
- **Absolute mode**: running `<lang>/qg.sh` (or `qg`) **without** `--base` (and without `QG_BASE_REF`) measures the current state once, with no baseline. Exit 0 always, except if `.qg.yaml` defines `absolute_thresholds` and some metric violates a threshold (exit 1). Useful when there is no base ref (e.g. legacy without a reference PR). JSON carries `mode: "absolute"`, `base_ref: null`, `schema_version: "1.1"`.

Comparative mode (with `--base`) does not change -- v1.1 is additive and backward-compatible.

### Tamper-resistance

The gate **ships and enforces its own rulesets** (`<lang>/rules/`). Quality
configs of the target project (`.eslintrc`, `clippy.toml`, `.stylelintrc`,
etc.) are **ignored by default** -- otherwise the dev loosens a rule in
their own repo and the gate becomes theater. Override only via the external
env var `QG_RULESET_DIR` (whoever RUNS the gate), never from `.qg.yaml`/a project file.

### React / Vue / Svelte / Angular = nodejs project

A project with `package.json` (even React/Vue/etc.) is covered by
`nodejs/qg.sh`. The `web` gate only covers **pure static HTML/CSS** (no
`package.json`). Framework rules go into the QG ruleset
(`nodejs/rules/`), never into the project config.

## Enforcement hook

The plugin also ships an **opt-in** `PreToolUse` hook (`hooks/pre-push-gate.sh`)
that blocks `git push` and `gh pr create` unless the gate passes for the
current HEAD, re-running `qg` against the branch upstream (falling back to
`origin/HEAD`, then absolute mode). Exporting `QG_BYPASS_REASON` overrides it
the same way it overrides the gate itself, and the hook fails **open** (never
blocks) on its own errors -- missing `jq`/`qg`, malformed input, or a
non-git directory. See [`docs/hooks.md`](docs/hooks.md).

## Supported languages

| Language | Script | Measured metrics | Prereqs |
|---|---|---|---|
| Rust | [`rust/qg.sh`](rust/README.md) | fmt, lint, build, test, complexity, coverage | cargo, cargo-llvm-cov, jq |
| Go | [`go/qg.sh`](go/README.md) | fmt, lint, build, test, complexity, coverage | go, gofmt, gocyclo, golangci-lint (optional), jq |
| Python | [`python/qg.sh`](python/README.md) | fmt, lint, build, test, complexity, coverage | python3, ruff, pytest, pytest-cov, radon, jq |
| Node.js | [`nodejs/qg.sh`](nodejs/README.md) | fmt, lint, build, test, complexity, coverage | node 18+, npm, npx, jq (prettier/eslint/c8 via npx) |
| Java | [`java/qg.sh`](java/README.md) | fmt, lint, build, test, complexity, coverage | java 17+, mvn, google-java-format, pmd, jq (jacoco plugin in the project) |
| Swift\* | [`swift/qg.sh`](swift/README.md) | fmt, lint, build, test, coverage | swift 5.9+, swift-format, swiftlint, jq (xcrun on macOS) |
| Kotlin | [`kotlin/qg.sh`](kotlin/README.md) | fmt, lint, build, test, complexity, coverage | java 17+, gradle, ktlint, detekt, jq (kover plugin in the project) |
| Web (HTML/CSS)\* | [`web/qg.sh`](web/README.md) | fmt, lint | node 18+, jq (prettier/stylelint/htmlhint via npx) |

\* `complexity` omitted in Swift -- see [`docs/languages/swift.md`](docs/languages/swift.md) section "Omitted metrics". `build`, `test`, `complexity` and `coverage` omitted in Web (static HTML/CSS has no build/test/complexity/coverage) -- see [`docs/languages/web.md`](docs/languages/web.md). A React/Vue/etc. project with `package.json` = **nodejs** project (`nodejs/qg.sh`), not web.

## Quick start

```bash
# Clone once
git clone git@github.com:xgodev/quality-gate.git ~/.quality-gate

# Run in your project (the dispatcher detects the language on its own)
cd /path/to/your/project
~/.quality-gate/qg --base origin/main
```

## Documentation

- [`docs/contract.md`](docs/contract.md) -- contract common to every language (CLI, exit codes, output, bypass, `.qg.yaml`).
- [`docs/output-format.md`](docs/output-format.md) -- detailed text and JSON formats.
- [`docs/consume.md`](docs/consume.md) -- how to integrate it in your project (local now; CI in V2).
- [`docs/hooks.md`](docs/hooks.md) -- the opt-in pre-push enforcement hook (blocks push/PR-create on a failing gate).
- [`docs/languages/rust.md`](docs/languages/rust.md) -- prereqs, metrics and troubleshooting for Rust.
- [`docs/languages/go.md`](docs/languages/go.md) -- prereqs, metrics and troubleshooting for Go.
- [`docs/languages/python.md`](docs/languages/python.md) -- prereqs, metrics and troubleshooting for Python.
- [`docs/languages/nodejs.md`](docs/languages/nodejs.md) -- prereqs, metrics and troubleshooting for Node.js.
- [`docs/languages/java.md`](docs/languages/java.md) -- prereqs, metrics and troubleshooting for Java.
- [`docs/languages/swift.md`](docs/languages/swift.md) -- prereqs, metrics and troubleshooting for Swift (complexity omitted).
- [`docs/languages/kotlin.md`](docs/languages/kotlin.md) -- prereqs, metrics and troubleshooting for Kotlin.
- [`docs/languages/web.md`](docs/languages/web.md) -- prereqs and troubleshooting for Web (HTML/CSS; only fmt+lint; React/Vue=nodejs).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). To add a new language with AI assistance, use the `add-quality-gate` skill in `skills/`.
