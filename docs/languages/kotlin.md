# Quality Gate -- Kotlin

Kotlin-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Kotlin assumes **Gradle (`gradle`/`gradlew`) + `build.gradle.kts`** as the canonical build in V1. The sentinel also detects `build.gradle` (Groovy DSL) but the gate has only been tested with the Kotlin DSL.

The presence sentinel is: `build.gradle.kts`/`build.gradle`/`settings.gradle.kts` at the root AND at least one `*.kt` source file under `src/`. Requiring a `*.kt` source under `src/` prevents pure-Java Gradle projects from being misclassified as Kotlin -- `build.gradle[.kts]` alone is a build-system sentinel shared by both languages, and Java projects routinely use the Kotlin Gradle DSL. If neither condition holds in the baseline, the gate emits a warning and exits 0.

## Prerequisites with install

### macOS

```bash
brew install openjdk@21 gradle ktlint detekt jq
# Make sure JAVA_HOME points to the installed JDK (see "brew info openjdk@21").
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install openjdk-21-jdk jq

# Gradle: install via SDKMAN (native apt is usually out of date):
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install gradle

# ktlint
curl -fsSLO https://github.com/pinterest/ktlint/releases/download/1.5.0/ktlint
sudo install -m 0755 ktlint /usr/local/bin/ktlint

# detekt
DETEKT_VERSION=1.23.7
curl -fsSLO "https://github.com/detekt/detekt/releases/download/v${DETEKT_VERSION}/detekt-cli-${DETEKT_VERSION}.zip"
unzip -q "detekt-cli-${DETEKT_VERSION}.zip" -d /opt
sudo ln -sf "/opt/detekt-cli-${DETEKT_VERSION}/bin/detekt-cli" /usr/local/bin/detekt
```

## Metrics -- what each one measures in Kotlin

### `fmt` -- formatting

Runs `ktlint 'src/**/*.kt' --reporter=plain`. Counts ONE line per violation in the format `file:line:col: msg`.

**Configuration:** if the project has an `.editorconfig` at the root, it is respected by ktlint. Without it, ktlint defaults (strict "Kotlin coding conventions", including multi-line function signatures).

**How to interpret a regression:** the PR introduced unformatted code. Fix: `ktlint 'src/**/*.kt' --format` (auto-fix) and review the diff.

### `lint` -- detekt

Runs `detekt --input src/main/kotlin --report txt:<log>`. Counts lines in the format `file:line:col: ... [RuleName]`.

**Configuration:** if the project has `detekt.yml` (default name) or another file passed via `--config`, it is respected. Without config, detekt defaults ("default" rules without opt-ins).

**How to interpret a regression:** the PR introduced an issue detekt detects. Fix: read `target/qg-logs/pr-lint.log`, identify the rule, fix the code. `@Suppress("RuleName")` only with a documented root cause.

### `build` -- compilation

Runs `gradle compileKotlin -q --no-daemon`. Counts `file.kt:line:col: error:` lines if exit code != 0.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate.

### `test` -- failing tests

Runs `gradle test --rerun-tasks --no-daemon`. Counts the number N from the summary `N tests completed, F failed` (gradle prints this line per test module; the gate takes the LAST occurrence).

`--rerun-tasks` is ESSENTIAL: without it, gradle marks the `:test` task as `UP-TO-DATE` between consecutive runs and does not re-execute, returning 0 even when tests are failing. The project's `build.gradle.kts` must have `tasks.test { ignoreFailures = true }` so the build does not abort.

**Tool error vs regression:** if gradle hangs (OOM, JVM crash), it does not produce a "tests completed" line -- it does not count as a test failure. These cases are a tool error and the user must investigate.

**How to interpret a regression:** tests that passed now fail. Fix: run `gradle test --info`, read the error, fix it.

`@Ignore` (JUnit 4) or `@Disabled` (JUnit 5) is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- complexity

Runs the same `detekt` as `lint`, but counts only matches of the specific rules:

- `CyclomaticComplexMethod` (default threshold = 15)
- `ComplexCondition` (default threshold = 4 boolean expressions)
- `NestedBlockDepth` (default threshold = 4)
- `LongMethod` (default threshold = 60 lines)
- `LongParameterList` (default threshold = 6 function parameters)

**How to interpret a regression:** the PR introduced a function above some threshold. Fixes: extract sub-functions; replace `if/else` chains with `when` or polymorphism; use early-return.

### `coverage` -- line coverage

Runs `gradle koverXmlReport --no-daemon` and parses `build/reports/kover/report.xml`. Computes `% covered` from the root counter `<counter type="LINE" missed="M" covered="C"/>`.

Kover uses the same XML format as JaCoCo. The target project needs the `kover` plugin applied: `id("org.jetbrains.kotlinx.kover") version "0.8.3"` in `plugins{}`.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test; or (with discretion) raise the margin in `.qg.yaml`.

## Common troubleshooting

### `Cannot find a Java installation matching: {languageVersion=17, ...}`

Gradle cannot find the JDK at the version required by `jvmToolchain(N)` in `build.gradle.kts`. Fix: adjust `jvmToolchain` to the installed version (`jvmToolchain(21)` if you have JDK 21) OR install the required JDK and set `JAVA_HOME`.

### `gradle test` reports 0 failures even with a failing test

Gradle caches the `:test` task output as `UP-TO-DATE`. The gate already uses `--rerun-tasks` but if you run `gradle test` manually without that flag, you hit the cache. Fix: always `gradle test --rerun-tasks` or `gradle clean test`.

### `kover` plugin not applied, coverage returns 0

The target project needs:

```kotlin
plugins {
    id("org.jetbrains.kotlinx.kover") version "0.8.3"
}
```

And the XML report is generated at `build/reports/kover/report.xml` after `gradle koverXmlReport`.

### Stale baseline cache after changing the base branch

```bash
~/.quality-gate/kotlin/qg.sh --base origin/main --refresh-baseline
# OR
rm -rf /tmp/qg-baseline-kotlin
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

None. Kotlin supports the 6 reserved metrics with official tools (ktlint, detekt, gradle compileKotlin/test, kover).

## Extra metrics

None in V1. Future candidates:
- `vuln` via `gradle dependencyCheckAnalyze` (OWASP Dependency-Check) -- vulnerabilities in deps.
- `binary_compat` via `kotlinx-binary-compatibility-validator` -- breaking API changes.
- `unused_deps` via `gradle nebula.dependency-lock` or similar.

To add, follow the contract (section "Extending") and `skills/add-quality-gate/`.
