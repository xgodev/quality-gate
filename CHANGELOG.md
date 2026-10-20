# Changelog

## [Unreleased]

Added: the baseline and the PR are now measured **concurrently** (`--parallel` /
`--no-parallel`, `QG_PARALLEL`). A comparative run measures two independent
trees -- the archive extracted under `--baseline-dir` and the working copy --
so running them at the same time is the one parallelism that cannot change a
number: neither side can see the other's sources, build cache, target dir or
logs. Wall-clock becomes roughly the slower side instead of the sum. Each side
now writes its metrics to its own TSV under `--log-dir` (`side-base.tsv`,
`side-pr.tsv`) through a `qg_measure_base_side` / `qg_measure_pr_side` pair in
every gate, and the shared driver is `lib/parallel.sh`. Default: on from 4
usable cores, sequential below that, because two concurrent builds on two cores
trade a context-switch storm for no wall-clock and risk the OOM the contract
classifies as a tool-error; the core count honors the cgroup CPU quota, since
`nproc` inside a container reports the HOST's cores. A side that dies (ICE,
OOM, killed) is exit 2 with an `::error::` that says it is infrastructure and
suggests `--no-parallel` -- never a regressed metric. (#18)

Metrics *within* a side are deliberately NOT parallelised: `fmt`, `lint`,
`build`, `test` and `coverage` of one directory share that directory's build
cache and the build systems serialise on its lock, so it would buy a lock wait
while two tools fight for the same cores.

Fixed (found while building the above, and a hazard already present in
sequential runs): with an operator-set `CARGO_TARGET_DIR`, both Rust trees
shared one build dir -- and two checkouts of the same workspace produce the
SAME crate metadata hash, so one side could link the other's artifacts. The
Rust gate now gives each side its own dir under it (`.../qg-base`,
`.../qg-pr`); the cargo default (a per-tree `./target`) is already isolated and
is left alone.

Also: `--baseline-dir` may legitimately point at the working tree itself (or at
a directory inside it), and then the two "sides" are one directory sharing one
`.qg-venv`/`target/`/coverage file. Overlapping trees are detected
(`qg_sides_isolated`, symlinks resolved) and measured sequentially with a
`::notice::`, even when `--parallel` was passed explicitly.

Docs: `docs/consume.md` gained a section on keeping the toolchain cache warm
across containerized runs -- a named volume plus the one env var per language
(cargo registry + target, GOMODCACHE/GOCACHE, maven repo, GRADLE_USER_HOME, npm
cache, PIP_CACHE_DIR, the SwiftPM cache path), with the two warnings that
matter: the cache is build input and never measurement input, and one volume
shared by two concurrent runs is a lock fight.

Tests: new `tests/parallel.bats` -- the sides really overlap in time, numbers
are identical with `--parallel` and `--no-parallel`, a dead side is exit 2 in
both modes, overlapping trees fall back to sequential, the cgroup/core
threshold decides `auto`, every gate wires the same driver exactly once, and a
cached baseline measures only the PR side.

## [1.2.0] -- 2026-10-20

Added: `--quick` / `QG_QUICK=1`, a sanctioned fast pre-PR mode. A full
comparative run on a compiled language costs enough wall-clock that developers
reach for `QG_BYPASS_REASON` instead -- a bypass that carries no information at
all. Quick mode keeps the cheap blocking metrics (fmt, lint, build, test) and
defers the expensive ones: they are NOT measured, NOT compared, reported with
verdict `skipped` and `null` numbers, and excluded from the exit code. The
document declares `schema_version: "1.2"` plus a top-level `"quick": true` so a
consumer can reject a partial report, and every quick run warns on stderr that
it is never a substitute for the full gate in CI. A quick run never writes the
base-metrics cache, which later runs read -- caching its numbers would hand a
full run a fabricated baseline. Non-quick output is byte-identical to 1.1.1.

The deferred set is per-language (`QG_QUICK_DEFERRED` in each `<lang>/qg.sh`),
because a metric is only deferrable when not measuring it actually saves work: a
metric that comes out of an invocation the gate performs anyway is a byproduct,
and deferring it would discard a number already in hand. go/python/nodejs/kotlin
defer `complexity` + `coverage`; rust defers `coverage` only (`complexity` rides
the `lint` clippy pass); java defers `complexity` only (`coverage` rides the
jacoco-bound `mvn test`); swift defers `coverage` and additionally drops
`--enable-code-coverage` from its test run, so the instrumented build never
happens; `web` defers nothing and says so. (#18)

Docs: `skip_metrics` in `.qg.yaml` is now documented for what it is --
**accepted, shape-validated and then ignored by every gate**. It was specified
with behavior no gate implements (expiry warnings, dropping a metric), and a
metric a project file can switch off is a tamper surface by the same law that
keeps project lint configs out. The governed ways to measure less belong to
whoever runs the gate: `--quick` and `QG_BYPASS_REASON`.

Tests: removed `tests/hook-pr.bats` and the `qg_hook_path`/`qg_make_stub_plugin`
helpers. The PR hook lives in the `xgodev` plugin, not here; the suite resolved
its path through `QG_REPO_ROOT/../..` (the pre-extraction `tools/quality-gate/`
layout) and all 20 tests had been failing with exit 127 on a path outside the
repo. `tests/README.md` also described a `.github/workflows/tests.yml` that does
not exist and `bats tools/quality-gate/tests/` paths that do not resolve.

Docs: `CONTRIBUTING.md` pointed at `skills/add-quality-gate/` for the
new-language checklist and listed it in the repo structure -- that skill ships
with the plugin, not with this repo. The structure listing also omitted `lib/`,
`hygiene/`, `tests/`, `gate.yml`, `CHANGELOG.md` and `CLAUDE.md`.

Docs: example branches and bypass reasons used an internal ticket prefix
(`INT-1234`, `INT-9999`); replaced with generic names, and the one Portuguese
comment left in `.gitignore` is now English.

Docs: `docs/consume.md` still told the reader to clone `xgodev/claude-plugin`
and run `~/.claude-plugin/tools/quality-gate/<lang>/qg.sh`, a layout that stopped
existing when the gate was extracted into this repo and shipped as images.
Rewritten around `docker run`, with the quick-mode options and smoke test.

Performance (rust): `lint` and `complexity` now come from ONE `cargo clippy`
invocation per side instead of two. The two passes differed only in lint flags,
and clippy receives those through the `CLIPPY_ARGS` environment variable, which
is part of cargo's fingerprint -- so the second pass reported
`Dirty <crate>: the environment variable CLIPPY_ARGS changed` and recompiled the
whole measured scope, one of four full builds per side. The fused pass keeps
`-D warnings` (lint semantics unchanged) and pins the 4 complexity lints at warn
level with `--force-warn`, which overrides the `warnings` group -- a plain `-W`
does not, whatever the flag order, and the complexity violations would then be
counted as lint errors too. `tests/rust-qg.bats` asserts a single clippy
invocation (PATH stub) and numeric parity with the two old passes on both the
baseline and the regressed fixture, which are kept as oracles. Same shape as the
existing `test`+`coverage` fusion. (#18)

Fix (tests): `rust/test-fixtures/regressed` was declared with the same package
name as the baseline fixture, so with a shared `CARGO_TARGET_DIR` the two
fixtures clobbered each other's artifacts and the `count_lint`/`count_test`/
`count_complexity` tests failed depending on which compiled last. Renamed to
`qg-regressed-fixture`.

## [1.1.1]

Fix (go): `coverage` counted generated code. `go test -coverprofile` counts
every statement of every package -- since Go 1.22 even packages without tests
-- and the canonical generated/vendored **dir** ignore only reaches
`gofmt`/`gocyclo`, which scan by path. A project that commits its generated
code (a `gen/` tree, a generated `cmd/<app>/main.go`) therefore dragged every
untested generated statement into the denominator: in the case that surfaced
this, 251 of 368 statements (68%) were generated and
`absolute_thresholds.coverage: 100` was unreachable however well the source was
tested. The Go gate now drops from the profile, before computing `total:`,
every file whose header matches the Go convention for generated code
(`^// Code generated .* DO NOT EDIT\.$` before the `package` clause,
https://go.dev/s/generatedcode). The marker is the language convention, not a
project setting, so there is nothing to configure and nothing to tamper with;
a profile entry that cannot be resolved to a file inside the module declared in
`go.mod` is kept, so a doubt never under-counts. New `go/test-fixtures/generated`
(covered source + uncovered generated `gen/gen.go`) reaches 100%, and
`tests/go-qg.bats` also asserts a file without the marker is never filtered.
Documented in `docs/contract.md` (new LAW section) and
`docs/languages/go.md`. (#21)

## [1.1.0]

Feature: `.qg.yaml` `system_packages` -- a project declares the OS packages its
build links (the C libraries behind FFI/`*-sys` crates, cgo, native node addons,
…) and the `qg` dispatcher installs them once, before any language gate, so the
baseline and the PR build against the same set. Keeps the shared images lean and
generic instead of baking a project's libraries in.

The list lives in a file the developer under test controls, so the project only
DECLARES -- the runner DECIDES: without `QG_ALLOW_SYSTEM_PACKAGES=1` from
whoever RUNS the gate the declaration is a `::warning::` and nothing is
installed (same trust boundary as `QG_RULESET_DIR`). Otherwise a repo could
have the gate install arbitrary packages as root, maintainer scripts and all,
or drop a distro `cargo`/`golang-go` on `/usr/bin` that shadows the toolchain
the image pins. Entries are validated as Debian package names
(`[a-z0-9][a-z0-9._+-]*`); anything else -- notably a leading dash, which
`apt-get` would read as a FLAG -- is exit 2, not a silent skip. The install runs
only as root and never calls `sudo` (it would hang on a password prompt in CI,
or grant the repo under test root on the runner); non-root and no-`apt-get` are
`::warning::` + continue. A failed install is exit 2, never a code verdict.
Tests in `dispatcher.bats` cover opt-in, both rejections, the apt failure, the
non-root path and the no-apt path.

Docs: the per-language docs claimed the target project's quality config was
respected -- `pyproject.toml [tool.ruff]`, `.golangci.yml`, `rustfmt.toml`,
`.prettierrc`/`eslint.config.*`, `.editorconfig`/`detekt.yml`,
`.swift-format`/`.swiftlint.yml`, a project `pmd-ruleset.xml`. The code has
always done the opposite (tamper-resistance: every tool is invoked with QG's
own ruleset and the flags that suppress project-config discovery), so the docs
were the only thing disagreeing with the contract. Every `**Configuration:**`
paragraph and every `Runs ...` command now states the real invocation, and each
`Fix:` command carries the gate's config so a local fix converges on the gate
instead of away from it. Python gains a "Reproduce the gate's verdict locally"
section -- the sharp case is `line-length`, where a project configured wider
formats every line further from the gate's 88 and collects an `E501` each.
Also corrects `docs/languages/python.md`'s build-system section, which said
poetry/pdm/uv were unsupported while the image ships all four and the gate
honors the project's lockfile. Docs only -- no behavior change. (#19)

## [1.0.2]

Fix: a git-lfs repo could not be gated at all. `git archive` runs the repo's
configured filters, so on an LFS checkout it needs `git-lfs` on PATH and every
blob in the local object store -- inside the images it has neither, and the run
died with `git-lfs: not found` / `the remote end hung up unexpectedly`, exit 2,
before measuring anything. The extraction now moves to a single shared
implementation, `lib/baseline-archive.sh` (sourced by all 8 `<lang>/qg.sh`,
replacing 8 copies of the same block), which neutralizes `filter.lfs.*` and
extracts LFS paths as pointer files -- offline, fast, deterministic, and
announced with a `::notice::` rather than done silently. Installing git-lfs in
the images was rejected: it would materialize the blobs (1.6 GB on the repo
that surfaced this) to measure binary payload that no metric reads.

Fix: an extraction failure printed a generic "try `git fetch origin`" because
git's stderr went to `/dev/null`. The `::error::` now quotes git's own message,
which is what identified the LFS cause above.

Fix: the hygiene scan no longer runs after a tool error (exit 2). That run
measured nothing, so the tool error is the only actionable finding -- burying it
under hundreds of hygiene warnings is how a reader concludes it worked.

Fix: the hygiene scan follows what git says the repo owns (tracked + new files;
ignored paths and nested checkouts excluded) instead of walking the tree. A
nested checkout (vendored clone, worktree, agent scratch dir like
`.solvers/issue-N`) previously multiplied every finding once per copy.

## [1.0.0] - [1.0.1]

Feature (#5-#11): per-language Docker images on GHCR
(`ghcr.io/xgodev/quality-gate/<lang>`), each carrying the full gate shell plus
only that language's toolchain. All build locally and pass an in-container e2e
smoke (gate runs against the language's baseline fixture and produces a verdict
with every metric measured); each enforces the gate's OWN ruleset, never the
mounted project's config. Sizes: go 921MB, java 666MB, kotlin 872MB, nodejs
1.16GB, web 1.13GB, python 1.2GB, rust 1.72GB, swift (multi-stage). Tooling
notes worth remembering:
- **go**: golangci-lint is PINNED to v1.64.8 -- v2 rewrote the config schema and
  rejects the shipped v1 `.golangci.yml` (exit 3), which silently degrades the
  gate to the `go vet` fallback; and its installer is fetched from the release
  TAG (not `master`, whose checksum table was stale and never verified).
- **nodejs/web**: prettier/eslint/typescript/c8 (node) and
  prettier/stylelint/htmlhint (web) are pre-installed at pinned versions so
  `npx` needs no registry at runtime (node smoke verified under `--network none`).
- **python**: ruff/radon/pytest/pytest-cov plus the poetry/pdm/uv/pipenv
  resolvers, so a project's lockfile manager is honored (never a silent pip).
- **java**: google-java-format + PMD from pinned release artifacts; the
  google-java-format launcher passes the JDK 21 `--add-exports` flags.
- **kotlin**: gradle + ktlint + detekt from pinned releases (detekt's launcher
  is `bin/detekt-cli`).
- **swift**: swiftlint + swift-format compiled from source (pinned tags) in a
  builder stage, binaries copied into the runtime -- no prebuilt Linux binaries
  exist.

Release (#12): `build-publish.yml` now publishes each image on a `vX.Y.Z` tag
with three tags -- the exact `:vX.Y.Z`, a moving major `:vX` (re-pointed every
release, what consumers pin), and `:latest`. A plain `main` push refreshes only
`:latest`. Release process and the `:v1` compatibility promise documented in
`CONTRIBUTING.md`.

Optimization (#13): trimmed the per-language Docker images. The gate copy
(`/opt/quality-gate`) no longer carries `test-fixtures/` or `tests/` -- those
serve the bats suite, never the runtime -- via `.dockerignore`, shrinking that
layer from ~344MB to ~0.6MB across every image. The rust image additionally
drops the `rust-docs` component and leftover cargo/rustup caches. Measured
rust image: **2.06GB -> 1.72GB (-340MB, -16.5%)**; e2e smoke (absolute mode
against the rust baseline fixture, inside the container) still passes with all
six metrics measured. The `.dockerignore` change benefits every language image.

## [0.4.0]

Changed: distribution moved to the single `xgodev-plugins` marketplace
(hosted in `xgodev/claude-plugin`, which lists this repo as a GitHub
source). This repo's own marketplace (`xgodev-quality-gate`) is retired
and `.claude-plugin/marketplace.json` removed -- BREAKING for the install
path only; the plugin itself is unchanged. Existing users: uninstall
`quality-gate@xgodev-quality-gate`, remove the `xgodev-quality-gate`
marketplace, add `xgodev/claude-plugin`, install
`quality-gate@xgodev-plugins`. README install section updated.

## [0.3.1]

Fix: the plugin failed to load in 0.3.0 with "Duplicate hooks file detected".
Claude Code auto-loads the standard `hooks/hooks.json`, and `plugin.json` ALSO
declared `"hooks": "./hooks/hooks.json"` -- the manifest key is only for
*additional* non-standard hook files, so the double registration broke the
whole plugin. Removes the manifest `hooks` key (auto-discovery is enough),
flips the bats test that asserted the buggy key, and corrects the
`docs/hooks.md` Registration section.

## [0.3.0]

Feature: opt-in pre-push enforcement hook. A bundled `PreToolUse` hook
(`hooks/pre-push-gate.sh`, declared in `hooks/hooks.json`) blocks `git push`
and `gh pr create` unless the gate passes for HEAD. It re-runs `qg` against the
branch upstream (`@{upstream}` -> `origin/HEAD` -> absolute mode), denies on
`qg` exit 1 (regressed/threshold) or 2 (tool error), and allows on 0
(passed/bypassed) or 3 (no supported language). Only non-code pushes are
exempt: a pure deletion (`--delete`/`-d`, or all-`:refspec`/`refs/tags/...`
refspecs) or a tag-only push (`--tags` with no branch refspec); a tag/delete
mixed with a real code refspec (e.g. `git push origin main --tags`) is gated.
Bypass is inherited: exporting `QG_BYPASS_REASON` makes the gate pass. The hook
fails OPEN on its own errors (missing `jq`/`qg`, malformed stdin, non-repo) so a
broken hook never bricks git. Adds `tests/hook-prepush.bats`. Docs: `docs/hooks.md`.

## [0.2.5]

Fix (#2): all 8 gates (`rust`/`go`/`python`/`nodejs`/`java`/`kotlin`/`swift`/`web`) now populate git submodules in the baseline checkout. `prepare_baseline` uses `git archive`, which does **not** expand submodules, so for any repo whose build depends on a submodule the baseline dirs were empty: the base build failed, base metrics were undercounted, and every PR was reported as a false `regressed` (the flagged files being pre-existing base-branch debt the base run simply could not measure). A new `_qg_extract_submodules` helper (in each `<lang>/lib/measure.sh`) walks the submodules registered at the base ref and extracts each at the exact commit it is pinned to -- sourced from the working tree's already-initialized submodule object store -- recursing into nested submodules. It is a no-op for repos without `.gitmodules`, never aborts the gate, and emits a `::warning::` (advising `git submodule update --init --recursive`) when a submodule cannot be extracted. Adds unit bats in all 8 `tests/<lang>-qg.bats` covering extraction-at-pinned-commit and the no-submodule no-op.

## [0.2.4]

BREAKING (marketplace ID, again): renames marketplace `name` from `xgodev` to `xgodev-quality-gate`. The previous `xgodev` collided with other `xgodev/*` marketplaces (e.g. `xgodev/claude-plugin` umbrella, which also declares itself as `xgodev`). Scoping the name to the repo (`xgodev-quality-gate`) removes the collision. Install command is now `/plugin install quality-gate@xgodev-quality-gate`. Anyone who already added the marketplace must remove and re-add it.

## [0.2.3]

BREAKING (marketplace ID): `marketplace.json` `name` is now `xgodev` (the org), not `quality-gate` (which collided with the plugin name). Install command is now `/plugin install quality-gate@xgodev`. Anyone who already added the marketplace must remove and re-add it: `/plugin marketplace remove quality-gate` then `/plugin marketplace add git@github.com:xgodev/quality-gate.git`. README updated.

## [0.2.2]

Fix (#1): all 8 gates (`rust`/`go`/`python`/`nodejs`/`java`/`kotlin`/`swift`/`web`) no longer return a silent `verdict=passed` / `metrics=[]` / `duration_seconds=0` when the default cache directory (`/tmp/qg-baseline-<lang>`) exists but is empty or incomplete (`/tmp` pruned, prior run died mid-extract, etc.). `prepare_baseline` now writes a `.qg-baseline-prepared` sentinel on success; the cache is reused only if the sentinel is present, and a stale/partial directory is re-extracted. Caller-supplied `--baseline-dir` keeps current semantics (no sentinel check). Adds an E2E regression bats in `tests/rust-qg.bats` covering the issue #1 scenario.

## [0.2.1]

Fix: `java`/`kotlin` `--detect` no longer collide on Gradle projects. Pure-Java projects using `build.gradle[.kts]` were classified as both `java` AND `kotlin`, causing the Kotlin gate to invoke a non-existent `compileKotlin` task; pure-Kotlin projects had the mirror problem. Detection now requires `>=1 *.java` (resp. `*.kt`) source under `src/` in addition to the Gradle sentinel. Maven (`pom.xml`) detection unchanged; mixed Java+Kotlin Gradle projects still match both gates. Adds cross-language disambiguation bats in `tests/dispatcher.bats`, `tests/java-qg.bats`, `tests/kotlin-qg.bats` covering 4 disambiguation cases + the mixed control.

## [0.2.0]

Full English translation (docs + runtime + skills); English-only triggers; add-quality-gate moved under skills/.

## [0.1.0]

Initial release: the Quality Gate dispatcher + per-language gates (Rust, Go, Python, Node.js, Java, Swift, Kotlin, Web) + the `quality-gate` skill.
