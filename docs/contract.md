# Quality Gate Contract (v1)

Contract version: **1.x** (`QG_CONTRACT_VERSION=1`). JSON `schema_version`: `1.1`.

This document defines what **every** `<lang>/qg.sh` must comply with. Changes here require updating ALL existing scripts.

v1.1 is **additive and backward-compatible**: comparative mode (with `--base`) does not change. The additions are `--detect`, absolute mode (`--base` optional), the `.qg.yaml absolute_thresholds` block, the `mode` field in the JSON, and the consolidated verdict enum. `QG_CONTRACT_VERSION` stays `1`.

## CLI

```
<lang>/qg.sh [--base <git-ref>] [options]
<lang>/qg.sh --detect

Options:
  --detect              Short-circuits: detect whether the language exists at
                        the project root. Prints the slug + exit 0 if yes, exit 1 if not.
  --base <ref>          Ref to compare against (e.g. origin/main, develop). If absent
                        (and no QG_BASE_REF), the gate runs in ABSOLUTE MODE.
  --baseline-dir <dir>  Path to an already-prepared baseline. Skips git archive extraction.
  --cov-margin <pp>     Coverage tolerance in pp (decimal). Default: 1.0
  --log-dir <dir>       Where to write per-step logs. Default: target/qg-logs
  --refresh-baseline    Re-extract baseline even if a cache exists.
  --force-full          Skip fast-path; measure everything even if nothing changed.
  --format text|json    Output format on stdout. Default: text.
  -h, --help            Show help.
```

## `--detect`

`<lang>/qg.sh --detect` short-circuits BEFORE any other validation (it is the first thing after arg parsing, before the `--base`/`--format`/prerequisite checks):

- Checks whether the language sentinel exists at the project root (`git rev-parse --show-toplevel 2>/dev/null || pwd`).
- Sentinel present -> prints the language slug to stdout (e.g. `rust`) and **exit 0**.
- Absent -> nothing on stdout, **exit 1**.
- Reuses the SAME sentinel used in the "language absent in baseline" / fast-path check. Does not duplicate the regex.

Reserved sentinels per language:

| Language | Sentinel |
|---|---|
| rust | `Cargo.toml` |
| go | `go.mod` |
| python | `pyproject.toml` or `setup.py` or `setup.cfg` or `requirements*.txt` |
| nodejs | `package.json` |
| java | `pom.xml`, OR (`build.gradle`/`build.gradle.kts` AND `>=1 *.java` under `src/`) |
| swift | `Package.swift` |
| kotlin | (`build.gradle.kts`/`build.gradle`/`settings.gradle.kts`) AND `>=1 *.kt` under `src/` |

For the JVM gates, `build.gradle[.kts]` alone is a build-system sentinel shared by Java and Kotlin projects (Java projects routinely use the Kotlin Gradle DSL). Detection therefore requires a source file of the language under `src/` so that pure-Java projects are not classified as Kotlin and vice-versa. Mixed Java+Kotlin Gradle projects continue to match both gates.

Consumers (the `quality-gate` skill) iterate `<lang>/qg.sh --detect`, collect the ones that exit 0 and run only those -- no hardcoded sentinel table.

## Absolute mode (`--base` optional)

If `--base` AND `QG_BASE_REF` are both absent -> **absolute mode** (not an error; does not exit 2).

- **Skips** baseline provisioning entirely (no `git archive`, no `--baseline-dir`).
- **Skips** fast-path (with no base there is no diff -- always measures full).
- **Skips** the "language absent in baseline" check (there is no baseline).
- Runs the measurement functions **once**, in `.`.
- Pass/fail: **exit 0 ALWAYS**, except if `.qg.yaml` defines `absolute_thresholds` and some measured metric violates one -> **exit 1**.

`absolute_thresholds` is ignored in comparative mode (there the base/PR comparison + `cov_margin` is what rules).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No regression / no violation (PASS, fast-path, bypassed, absolute mode with no violation or `--detect` with sentinel) |
| 1 | Comparative mode: >=1 metric regressed. Absolute mode: >=1 `absolute_thresholds` violated. `--detect`: sentinel absent |
| 2 | Setup error: missing tool, invalid baseline, invalid `.qg.yaml`, measurement tool broke, dependency resolution failed |

`--base` absent is no longer exit 2 -- it becomes absolute mode. `--detect` uses exit 1 only for "sentinel absent" (never exit 2).

**Tool error != regression.** Compiler segfault -> exit 2, not exit 1. Dependency resolution failure (network, corrupted lockfile, private registry without auth) -> exit 2, **never** a regressed `build`.

## Environment variables

| Name | Default | Use |
|---|---|---|
| `QG_BYPASS_REASON` | (empty) | Set -> gate exits 0 + audit log. See the Bypass section. |
| `QG_LOG_DIR` | `target/qg-logs` | Equivalent to `--log-dir`. CLI takes precedence. |
| `QG_BASE_REF` | (empty) | Equivalent to `--base`. CLI takes precedence. Empty + no `--base` -> absolute mode. |
| `QG_BASELINE_DIR` | (empty) | Equivalent to `--baseline-dir`. CLI takes precedence. |
| `QG_COV_MARGIN` | `1.0` | Equivalent to `--cov-margin`. CLI takes precedence. |
| `QG_REFRESH_BASELINE` | `0` | `1` equivalent to `--refresh-baseline`. |
| `QG_FORCE_FULL` | `0` | `1` equivalent to `--force-full`. |
| `QG_FORMAT` | `text` | Equivalent to `--format`. |
| `QG_RULESET_DIR` | (empty) | Override of the bundled `rules/` (tamper-resistance). Only honored if it comes from the ENVIRONMENT of whoever runs the gate -- NEVER from `.qg.yaml`/a project file. Empty -> uses `<QG>/<lang>/rules/`. |

## Text output (default)

Fixed structure in 3 blocks:

```
═══ Quality Gate — <lang> ═══
  branch:        <current branch>
  base ref:      <--base>
  baseline:      <path>
  cov margin:    <pp>pp
  logs:          <dir>/

── measuring base ──
[silent; logs in <log-dir>/base-*.log]

── measuring PR ──
[silent; logs in <log-dir>/pr-*.log]

metric        base       pr     verdict
─────────────────────────────────────────
fmt              0        0    ✅ same
lint             3        2    ✅ improved
build            0        0    ✅ same
test fails       0        1    ❌ regressed
complexity       7        7    ✅ same
coverage     82.3%    81.0%   ❌ regressed (margin: 1.0pp)

::error::PR regressed test fails, coverage -- see above.
```

Output in **English**. Identifiers (`improved`, `same`, `regressed`) in EN ASCII.

## JSON output (`--format json`)

Stdout receives ONLY the JSON. Progress messages go to stderr; detailed logs stay in `--log-dir`.

Schema validated against [`contract-v1.schema.json`](contract-v1.schema.json) (accepts `schema_version` `"1.0"` and `"1.1"`).

Top-level field **`"mode"`**: `"comparative"` | `"absolute"`. Absent => treat as legacy 1.0 `comparative`.

### Comparative mode

```json
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "rust",
  "branch": "feature/INT-1234",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 1234,
  "verdict": "regressed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "lint", "base": 3, "pr": 2, "delta": -1, "verdict": "improved" },
    { "name": "build", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "test", "base": 0, "pr": 1, "delta": 1, "verdict": "regressed" },
    { "name": "complexity", "base": 7, "pr": 7, "delta": 0, "verdict": "same" },
    { "name": "coverage", "base": 82.3, "pr": 81.0, "delta": -1.3, "margin": 1.0, "verdict": "regressed" }
  ]
}
```

`base_ref` stays a string. Metrics stay `{name, base, pr, delta, verdict}`.

### Absolute mode

```json
{
  "schema_version": "1.1",
  "mode": "absolute",
  "language": "rust",
  "branch": "feature/x",
  "base_ref": null,
  "started_at": "2026-05-15T10:00:00Z",
  "duration_seconds": 120,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt",        "value": 0,    "threshold": 0,    "verdict": "ok" },
    { "name": "lint",       "value": 3,    "threshold": 0,    "verdict": "violated" },
    { "name": "complexity", "value": 7,    "threshold": null, "verdict": "reported" },
    { "name": "coverage",   "value": 82.3, "threshold": 80,   "verdict": "ok" }
  ]
}
```

- `base_ref: null`.
- Each metric: `{ "name", "value", "threshold" (number|null), "verdict" }`.
  - Per-metric `verdict` in `"ok"` (threshold defined, not violated) | `"violated"` (threshold violated) | `"reported"` (no threshold -- informational).
- Global `verdict` in `passed|failed|bypassed`. `failed` = >=1 metric `violated`. No violation (or no threshold) -> `passed`.

### Consolidated verdict enum

Global schema v1.1 `verdict`: **`passed | regressed | failed | bypassed`**.
- `regressed` only in comparative mode.
- `failed` only in absolute mode.
- `passed`/`bypassed` in both modes.

Metric `verdict`: comparative uses `same|improved|regressed`; absolute uses `ok|violated|reported`. The schema discriminates via `if mode`.

General rules:

- A metric omitted by the language **does not appear** in the list.
- An extra metric (beyond the 6) appears with the same schema.

## Governed bypass

Env var `QG_BYPASS_REASON="<reason>"`:

- Set and non-empty: gate **always** exits 0.
  - Text: a `::warning::QG bypass active -- reason: <reason>` block + a `::warning::This run did not validate metrics. Audit log: <path>` line.
  - JSON: `verdict: "bypassed"`, `bypass_reason: "<reason>"`, `metrics: []`.
- Empty/unset: normal behavior.

**Audit log:** `<log-dir>/bypass.log` with UTC timestamp, branch, user (`git config user.email`), reason. V2 centralizes.

No equivalent CLI flag. The env var adds friction deliberately.

## Deterministic dispatcher (`qg` at the root)

The root of the gate repo ships a `qg` executable (`~/.quality-gate/qg`).
**100% shell detection, zero AI**: it discovers the target project's language(s) via
`<lang>/qg.sh --detect` and runs the matching gate(s). The consumer skill
ONLY calls this script -- it never iterates `<lang>/qg.sh` on its own nor keeps
a hardcoded sentinel table.

- **Sub-project discovery (hybrid):**
  - If `<target>/.qg.yaml` exists with a `projects:` block -> uses ONLY that list.
    Each item: `path:` required, `lang:` optional. For each `path`, runs
    `<lang>/qg.sh --detect` inside `<target>/<path>` (if `lang:` given, tests
    only that one; otherwise tests all).
  - Otherwise -> root detection: for each `<root>/*/qg.sh`, runs
    `(cd <target> && <s> --detect)`. Collects the ones that exit 0.
- **Execution:**
  - 0 matches -> stderr `::error::no supported language detected`, **exit 3**
    (deterministic code reserved for "no language").
  - 1 match -> runs `<lang>/qg.sh "$@"` in the right directory, forwards the exit code.
  - N matches -> runs all sequentially. **Global verdict = worst**: any
    exit != 0 -> exit != 0 (precedence: `2 > 1 > 3 > 0`). With `--format json`,
    emits an array `[{lang,...}, ...]` with a top-level `aggregate_verdict` field.
- Forwards flags (`--base`, `--format`, `--cov-margin`, `--log-dir`, etc.)
  intact to the `<lang>/qg.sh`.
- `qg --detect` -> lists the detected slugs (one per line), exit 0 if >= 1,
  exit 3 if 0.

### Exit code 3 reserved

| Code | Meaning |
|---|---|
| 3 | **Dispatcher:** no supported language detected in the target project |

Exit 3 is the **dispatcher's**, never an individual `<lang>/qg.sh`'s. Consumers
map: 3 -> "language out of scope", 2 -> tool/setup error, 1 -> regression/
threshold violated, 0 -> green.

## React/Vue/etc. do NOT become their own gate

A React, Vue, Svelte, Angular, etc. project = **nodejs project**, covered by
`nodejs/qg.sh` (sentinel `package.json`). Framework-specific rules go into
the **QG ruleset** (see "Tamper-resistance"), never into the target project's config.
The `web` gate only covers **pure static** HTML/CSS (no `package.json`).

## Tamper-resistance -- the ruleset belongs to QG (LAW, all languages)

**LAW:** the gate **ships and enforces its own rulesets**. Quality configs of the
target project (`.eslintrc`, `clippy.toml`, `pyproject.toml [tool.ruff]`,
`.swiftlint.yml`, `detekt.yml`, `.stylelintrc`, etc.) are **ignored by
default**. Otherwise the dev loosens a rule in their own repo and the gate becomes theater.

- Each `<lang>/` bundles a `rules/` directory with the canonical config.
- `<lang>/qg.sh` (via `lib/measure.sh`) invokes the tool pointing at the
  QG `rules/` **and with the flags that ignore local config**:

| Language | How QG forces its own ruleset |
|---|---|
| rust | `CLIPPY_CONF_DIR=<QG>/rust/rules`; `cargo fmt -- --config-path <QG>/rust/rules/rustfmt.toml` |
| go | `golangci-lint run -c <QG>/go/rules/.golangci.yml`; `gocyclo` threshold fixed in the script. `gofmt` has no config -> trivially tamper-proof |
| python | `ruff --config <QG>/python/rules/ruff.toml` (an explicit `--config` file makes ruff ignore the project's pyproject/ruff.toml); `radon` threshold fixed in the script |
| nodejs | `eslint --no-config-lookup --config <QG>/nodejs/rules/eslint.config.mjs`; `prettier --config <QG>/nodejs/rules/.prettierrc.json --no-editorconfig`; `tsc -p <ephemeral>` which `extends` `<QG>/nodejs/rules/tsconfig.base.json` (strict locked, independent of the project's tsconfig). QG's `tsconfig.base.json` is strict but JSX/React-Native-capable (`jsx: preserve` + the `qg-jsx-shim.d.ts` shim): parses `.tsx` without phantom TS17004/TS7026, but the dev does NOT loosen strictness (tamper rule still holds: QG's ruleset rules) |
| java | `pmd -R <QG>/java/rules/pmd.xml`; `google-java-format` (fixed style, no config) |
| swift | `swiftlint --config <QG>/swift/rules/.swiftlint.yml`; `swift-format --configuration <QG>/swift/rules/.swift-format` |
| kotlin | `detekt -c <QG>/kotlin/rules/detekt.yml`; `ktlint --editorconfig=<QG>/kotlin/rules/.editorconfig` |
| web | `stylelint --config <QG>/web/rules/.stylelintrc.json` (an explicit file overrides the project's .stylelintrc); `htmlhint --config <QG>/web/rules/.htmlhintrc`; `prettier --config <QG>/web/rules/.prettierrc.json --no-editorconfig` |

- **Override is external only:** an alternative ruleset only via env `QG_RULESET_DIR=<path>`
  set by whoever **runs** the gate (pipeline / conscious dev). **NEVER** read from
  a target project file (not even `.qg.yaml`, which the dev controls). Default
  is always = QG's bundled `rules/`.
- Content of `rules/`: community defaults (clippy 25/100/7/250, eslint
  recommended + prettier, ruff default, etc.). Fine calibration is V2 -- what the
  contract guarantees is the **mechanics** of not reading the project's config.

### LAW: fmt/lint/complexity measure SOURCE CODE (QG's canonical ignore)

**LAW:** the `fmt`/`lint`/`complexity` metrics measure **SOURCE CODE**.
**Generated/vendored** directories are excluded by a **CANONICAL ignore
owned by QG** (tamper-proof: **NEVER** read from the target project's
`.eslintignore` / `.prettierignore` / `.gitignore` / `.qg.yaml` -- the dev does not
loosen the scan). Measuring an artifact (a minified bundle in `build/`, a dep in
`vendor/`) inflates the number and makes the metric useless.

Canonical exclusion list (generated/vendored dirs): `node_modules/`,
`dist/`, `build/`, `out/`, `.next/`, `.nuxt/`, `.expo/`, `coverage/`,
`.turbo/`, `.cache/` (+ `.venv/`/`venv/` in Python, `vendor/` in Go) and
files `*.min.js`, `*.min.css`, `*.bundle.js`, `*.chunk.js`, `*-lock.json`,
`*.map`. Applied to EVERY measurement that scans files by path:

| Language | Mechanism of the canonical ignore |
|---|---|
| nodejs | `ignores` block (1st element, global ignore) in QG's `eslint.config.mjs` (lint+complexity); `prettier --ignore-path <QG>/nodejs/rules/.prettierignore` (fmt); `_qg_node_sources` excludes the dirs (build) |
| web | `prettier --ignore-path <QG>/web/rules/.prettierignore`; `_qg_web_css`/`_qg_web_html` prune from the canonical list + an explicit list for stylelint/htmlhint |
| python | `extend-exclude` in QG's `ruff.toml` (independent of respect-gitignore); `radon -i/-e` with the canonical list |
| go | `gofmt -l`/`gocyclo` filtered by the canonical list (classic vendor/); `./...` is already module-scoped |
| rust/java/kotlin/swift | no anti-pattern: cargo/mvn-pmd/ktlint-detekt are crate/`src/`-scoped; swift excludes `.build/` |

Override is **external only** (`QG_RULESET_DIR`), never from a project file --
same tamper rule as the ruleset.

## Per-repo config (`.qg.yaml` optional)

Read from the target project root if it exists. **Closed** schema -- unknown key -> exit 2.

```yaml
cov_margin: 2.0                       # override of the default 1.0
skip_metrics:
  - metric: complexity
    reason: "legacy crate, plan in INT-1234"
    until: "2026-09-01"               # ISO 8601
extra_fast_path_paths:
  - "^vendor/"
  - "^third_party/"
projects:                             # monorepo: closed list of sub-projects
  - path: backend
    lang: go
  - path: frontend                    # lang omitted -> dispatcher detects
```

### `projects` block (monorepo)

Read ONLY by the root `qg` dispatcher. **Closed** schema per item: allowed keys
= `path` (required), `lang` (optional). Unknown key -> exit 2.
If `projects:` exists, the dispatcher **ignores** root detection and uses only this
list. `lang:` does NOT select the ruleset (that is a tamper-surface) -- it only restricts which
`<lang>/qg.sh --detect` to test inside the `path`.

Full closed schema of `.qg.yaml`: `cov_margin`, `skip_metrics`,
`extra_fast_path_paths`, `absolute_thresholds`, `projects`.

Rules:

- `until` in the past -> script ignores the skip and resumes measuring/blocking (logs `::warning::skip of <metric> expired on <date>`).
- `skip_metrics` without `reason` or without `until` -> exit 2.
- The same schema applies to EVERY language.

### `absolute_thresholds` block (absolute mode)

Optional block, read ONLY in absolute mode:

```yaml
absolute_thresholds:
  fmt: 0
  lint: 0
  build: 0
  test: 0
  complexity: 10
  coverage: 80      # MINIMUM (coverage = higher is better)
```

- Closed schema: allowed keys under `absolute_thresholds` = the 6 reserved names + any extra metric the language declares. Unknown key -> exit 2.
- Counters (`fmt`/`lint`/`build`/`test`/`complexity` and counter extras): violation if `value > threshold`.
- `coverage` (and percentage extras): violation if `value < threshold` (it is a minimum).
- Any violation -> **exit 1**. No threshold defined, or no `.qg.yaml`, or no `absolute_thresholds` block -> **exit 0**, only reports (`verdict: reported`).
- Ignored in comparative mode.

## Reserved metrics

These 6 names are reserved -- if the language measures the metric, **use this exact name**:

| Name | Counts | Fails if |
|---|---|---|
| `fmt` | unformatted files | PR > base |
| `lint` | linter errors | PR > base |
| `build` | build errors | PR > base |
| `test` | failed tests | PR > base |
| `complexity` | complexity violations | PR > base |
| `coverage` | % lines covered | PR < base - margin |

**Omitting:** the language documents in `docs/languages/<lang>.md` why it has no tool. Does not print a text line, omits it in the JSON.

**Extending:** an extra metric with a unique snake_case ASCII name, same regression rule.

## Fast-path

Each `<lang>/qg.sh` defines a regex of "language source files":

- Rust: `\.rs$|^Cargo\.|build\.rs$|^rust-toolchain`

If `git diff --name-only <base>...HEAD` (+ staged + worktree) matches nothing and `--force-full` was not passed:
1. Prints the fast-path header (text) or `verdict: "passed"` with `metrics: []` (JSON).
2. Validates the syntax of modified shell scripts (`bash -n`).
3. Exit 0.

`extra_fast_path_paths` from `.qg.yaml` is added to the regex.

## Baseline

- Without `--baseline-dir`: `git archive <base>` into `/tmp/qg-baseline-<lang>` (cached). A successful extract writes a sentinel file `.qg-baseline-prepared`; the cache is reused only if the sentinel is present. A directory that exists without the sentinel (e.g. `/tmp` pruned, prior run died mid-extract) is treated as stale and re-extracted -- never reused. `--refresh-baseline` forces re-extraction regardless.
- **Submodules**: `git archive` does not expand git submodules, so after the archive each submodule registered at the base ref is extracted at the exact commit it is pinned to (sourced from the working tree's already-initialized submodule object store, recursing into nested submodules). Without this, a submodule-dependent build fails in the baseline, the base metrics undercount, and every PR is reported as a false `regressed` (#2). No-op for repos without `.gitmodules`; a submodule that cannot be extracted yields a `::warning::` and is skipped (never aborts the gate).
- With `--baseline-dir`: assumes the directory is ready, **including submodules** (CI checked out into a separate path with `git submodule update --init --recursive`). No sentinel check, no submodule extraction.
- Language absent in baseline (e.g. PR adds `Cargo.toml` for the 1st time): `::warning::language absent in baseline -- gate skipped` + exit 0. Reached only after a successful `prepare_baseline` (or with `--baseline-dir`) -- never as a side-effect of a corrupt cache.

## Per-language prerequisites

Each `<lang>/qg.sh` validates tools at the start. Missing: exit 2 with a clear message.

### LAW: every missing-tool message teaches how to install it (Linux + macOS)

**LAW:** EVERY `::error::` message for a missing or not-found tool / manager /
build-system / toolchain MUST include the install command for
**Linux AND macOS** and the consequence of ignoring it. Applies to:

- entries from `check_prereqs` (the `missing+=(...)` array of each `<lang>/qg.sh`);
- missing manager/build-system/toolchain errors in `<lang>/lib/*.sh` (e.g.
  `yarn.lock` + `yarn` absent, `poetry.lock` + `poetry` absent, `pom.xml`
  without Maven, channel pinned in `rust-toolchain` not installed).

Canonical format (ASCII, `--` never an em-dash):

```
::error::<cause> -- install: '<linux cmd>' (Linux) / '<macOS cmd>' (macOS) (<consequence if ignored>)
```

Examples: `yarn` -> `npm i -g yarn` / `brew install yarn`; `pnpm` ->
`npm i -g pnpm` / `brew install pnpm`; `poetry` -> `pipx install poetry` /
`brew install poetry`; `cargo-llvm-cov` -> `cargo install cargo-llvm-cov`
(both); `jq` -> `apt install jq` / `brew install jq`. If the tool is not
trivially installable (e.g. a build-system not supported by the gate), the right
action replaces `install:` (`open an issue / add-quality-gate`), but the
message stays actionable.

Common ones: `git`, `bash 4+`, `awk`, `tar`, `jq`.

## GNU/BSD compatibility

Scripts run on macOS dev (BSD) and Linux CI (GNU). Rules:

- No `sed -i` -- use `sed -e ... > tmp && mv tmp file`.
- No `grep -P` (not on BSD).
- No `awk gensub` -- use `gsub`.
- No `find -regex` -- use `find ... | grep -E`.

## Dependency resolution before build/test (mandatory)

Before measuring `build`/`test`/`coverage`, the script MUST resolve the dependency closure of the measured directory (both PR and baseline in comparative mode; the current directory in absolute mode). Measuring build without `node_modules`/venv/etc resolved produces a false regressed `build`.

| Language | Dependency resolution before build/test |
|---|---|
| nodejs | detect lockfile: `pnpm-lock.yaml`->`pnpm i --frozen-lockfile`; `yarn.lock`->`yarn install --immutable` if `.yarnrc.yml` present (Yarn Berry v2+), else `yarn install --frozen-lockfile` (Yarn classic v1); else `npm ci` (fallback `npm install` if there is no `package-lock.json`). Only if `node_modules/` absent or lockfile newer. |
| python | if there is `requirements*.txt`/`pyproject.toml` and no active venv with deps: create an ephemeral venv and `pip install -q -r ...` / `pip install -q .`. |
| java | `mvn` resolves on `compile`/`test`; ensure `-o` (offline) is NOT used; if resolution fails -> tool-error. |
| kotlin | `gradle` resolves on its own; ensure non-offline; if resolution fails -> tool-error. |
| go | `go build`/`go test` resolve via go modules; ensure `GOFLAGS=-mod=mod`; if download fails -> tool-error. |
| rust | `cargo` resolves on its own. No change. |
| swift | `swift build` resolves SwiftPM. No change. |

### The declared toolchain/build-system is authoritative (LAW)

The gate measures what the project **actually uses**. If the project declares a specific dependency manager, build-system or toolchain and the gate **cannot honor it exactly** (tool absent from PATH, pinned version not satisfiable, build-system not supported by the language gate), that is a **tool-error -> exit 2** with a clear message in the log pointing to the cause. **NEVER** silently substitute another tool/version/manager that would produce a different result.

Silent substitution masks the real cause with a misleading error and measures an artifact that does not match what CI/production will build -> a worthless verdict. Generalizes the nodejs LAW (`025d8e0`) to all languages.

Non-goal: the gate does **not** start implementing every build-system. An unsupported build-system = an honest tool-error (instruction: open an issue / `add-quality-gate`), not substitution.

| Language | Anti-pattern to fix | Correct behavior |
|---|---|---|
| **nodejs** | (DONE in `025d8e0`) lockfile + manager absent -> npm fallback | lockfile authoritative; manager absent = tool-error |
| **java** | `build.gradle`/`build.gradle.kts` (Gradle) present but the gate silently runs `mvn` | `pom.xml`->Maven (supported). Gradle (no `pom.xml`)-> tool-error: "the Java gate only supports Maven today -- open an issue / add-quality-gate". If `./mvnw` present, use the wrapper (pinned version), not the system `mvn`. |
| **python** | `poetry.lock`/`pdm.lock`/`uv.lock`/`Pipfile.lock` present but the gate uses `pip install` (a different resolver) | Detect the manager from the lockfile: `poetry.lock`->poetry; `pdm.lock`->pdm; `uv.lock`->uv; `Pipfile.lock`->pipenv; only `requirements*.txt`/`pyproject` without a lock->pip. Lock manager absent = tool-error, never pip. |
| **kotlin** | system `gradle` used ignoring `./gradlew` (pinned version in the wrapper) | If `./gradlew` present, use the wrapper; a wrapper error that would force a different-version system `gradle` = tool-error, not substitution. |
| **go** | `go.mod` with a `toolchain`/`go 1.x` directive not satisfied by the PATH `go`; build with a different version | Respect `GOTOOLCHAIN` (default `auto` downloads the pinned one). If download fails and the PATH version diverges from the pinned one -> tool-error, not a build with the wrong version. |
| **rust** | `rust-toolchain.toml`/`rust-toolchain` pinning a channel not installed; build with a different toolchain | `cargo`/rustup honors `rust-toolchain.toml`; the script does not force `+stable`/override. Pinned channel absent offline -> tool-error, not stable. |
| **swift** | `Package.swift` declares a `swift-tools-version` above the PATH `swift` -> degraded build | clear tool-error on the tools-version incompatibility. |
| **web** | N/A -- no manager/build-system (static). No change. | -- |

Message format (in the appropriate `$log` -- `abs-deps.log`/`pr-deps.log`/`abs-build.log` depending on the step):

```
::error::<specific cause> -- <user action> (silent substitution would produce an incorrect result)
```

The caller already emits `::error::failed to resolve/measure <lang> -- see <log>`; the detailed cause goes in the `$log`.

**Lockfile is authoritative (LAW):** if a lockfile is present but the corresponding manager is not on PATH (e.g. `yarn.lock` + `yarn` absent), that is a **tool-error -> exit 2** with a clear message in the log pointing to the missing manager -- **NEVER** fall back to another manager. Switching managers silently produces an incorrect resolution (different peer-deps across npm/yarn/pnpm) and masks the real cause with a misleading error (e.g. npm's `ERESOLVE` in a yarn project).

If dependency resolution **fails** (network, corrupted lockfile, private registry without auth, lockfile manager absent): that is a **tool-error -> exit 2** (`::error::failed to resolve <lang> dependencies -- <detail>`), **NOT** a regressed `build`.

## Numeric sanitization (`_num`, mandatory)

Every value that feeds `jq --argjson` (or arithmetic comparison / `awk`) MUST be sanitized to a number before use. Mandatory function in each `lib/measure.sh` and `lib/output.sh`:

```bash
# Ensures a number; anything non-numeric (empty, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}
```

- Counters with no result -> `0`.
- `coverage` with no tests / tool with no output -> `0` (never `"Unknown"`, never empty). In absolute mode, `coverage=0` with a defined threshold becomes `violated`; without a threshold becomes `reported`.
- Where the absence of a number indicates a **broken tool** (not "legitimate absence"), prefer tool-error (exit 2) to masking it with `0`. E.g.: `cargo llvm-cov` segfault = exit 2; `0 tests so no coverage` = `coverage 0` + continue.
- Apply `_num` at ALL `--argjson`/`awk`/comparison points in `lib/`.

## Forbidden

You cannot silence the gate without a real fix:

- Raise a local complexity threshold without recording it in `.qg.yaml` (with `until`).
- Mark tests as ignored just to "pass".
- Blanket-allow lints without a root cause.
- `--no-verify` on git hooks.

Root cause, or governed bypass, or `.qg.yaml` with `until`.

## Mandatory header in the script

Line 2 of each `<lang>/qg.sh`:

```bash
# QG_CONTRACT_VERSION=1
```

Validation tools read this to confirm compatibility.
