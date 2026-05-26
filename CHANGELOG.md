# Changelog

## [0.2.2]

Fix (#1): all 8 gates (`rust`/`go`/`python`/`nodejs`/`java`/`kotlin`/`swift`/`web`) no longer return a silent `verdict=passed` / `metrics=[]` / `duration_seconds=0` when the default cache directory (`/tmp/qg-baseline-<lang>`) exists but is empty or incomplete (`/tmp` pruned, prior run died mid-extract, etc.). `prepare_baseline` now writes a `.qg-baseline-prepared` sentinel on success; the cache is reused only if the sentinel is present, and a stale/partial directory is re-extracted. Caller-supplied `--baseline-dir` keeps current semantics (no sentinel check). Adds an E2E regression bats in `tests/rust-qg.bats` covering the issue #1 scenario.

## [0.2.1]

Fix: `java`/`kotlin` `--detect` no longer collide on Gradle projects. Pure-Java projects using `build.gradle[.kts]` were classified as both `java` AND `kotlin`, causing the Kotlin gate to invoke a non-existent `compileKotlin` task; pure-Kotlin projects had the mirror problem. Detection now requires `>=1 *.java` (resp. `*.kt`) source under `src/` in addition to the Gradle sentinel. Maven (`pom.xml`) detection unchanged; mixed Java+Kotlin Gradle projects still match both gates. Adds cross-language disambiguation bats in `tests/dispatcher.bats`, `tests/java-qg.bats`, `tests/kotlin-qg.bats` covering 4 disambiguation cases + the mixed control.

## [0.2.0]

Full English translation (docs + runtime + skills); English-only triggers; add-quality-gate moved under skills/.

## [0.1.0]

Initial release: the Quality Gate dispatcher + per-language gates (Rust, Go, Python, Node.js, Java, Swift, Kotlin, Web) + the `quality-gate` skill.
