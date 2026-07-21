# Changelog

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

Feature: `.qg.yaml` `system_packages` -- a project declares the OS packages its
build links (the C libraries behind FFI/`*-sys` crates, cgo, native node addons,
…) and the `qg` dispatcher installs them once, before any language gate, so the
baseline and the PR build against the same set. Keeps the shared images lean and
generic instead of baking a project's libraries in. `apt-get` only (no-op with a
`::warning::` where absent, e.g. local macOS); a failed install is exit 2, never
a code verdict; `QG_SKIP_SYSTEM_PACKAGES=1` skips it. Allowed as a top-level key
in every language gate; installed by the dispatcher. Tests in `dispatcher.bats`.

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
