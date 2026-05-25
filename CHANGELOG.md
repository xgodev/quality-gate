# Changelog

## [0.2.1]

Fix: `java`/`kotlin` `--detect` no longer collide on Gradle projects. Pure-Java projects using `build.gradle[.kts]` were classified as both `java` AND `kotlin`, causing the Kotlin gate to invoke a non-existent `compileKotlin` task; pure-Kotlin projects had the mirror problem. Detection now requires `>=1 *.java` (resp. `*.kt`) source under `src/` in addition to the Gradle sentinel. Maven (`pom.xml`) detection unchanged; mixed Java+Kotlin Gradle projects still match both gates. Adds cross-language disambiguation bats in `tests/dispatcher.bats`, `tests/java-qg.bats`, `tests/kotlin-qg.bats` covering 4 disambiguation cases + the mixed control.

## [0.2.0]

Full English translation (docs + runtime + skills); English-only triggers; add-quality-gate moved under skills/.

## [0.1.0]

Initial release: the Quality Gate dispatcher + per-language gates (Rust, Go, Python, Node.js, Java, Swift, Kotlin, Web) + the `quality-gate` skill.
