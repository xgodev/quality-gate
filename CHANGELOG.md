# Changelog

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
