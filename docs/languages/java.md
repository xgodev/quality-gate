# Quality Gate -- Java

Java-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Java assumes **Maven (`mvn`) + `pom.xml`** as the canonical build in V1. Gradle is detected by the sentinel (`build.gradle`/`build.gradle.kts`) -- the sentinel only prevents "language absent", but `count_build_errors` and `count_test_failures` run `mvn`. In a Gradle target project, these metrics need to be adapted (future).

The presence sentinel is: `pom.xml` at the root, OR (`build.gradle`/`build.gradle.kts` at the root AND at least one `*.java` source file under `src/`). Requiring a `*.java` source under `src/` prevents pure-Kotlin Gradle projects from being misclassified as Java -- `build.gradle[.kts]` alone is a build-system sentinel shared by both languages. If neither condition holds in the baseline, the gate emits a warning and exits 0.

## Prerequisites with install

### macOS

```bash
brew install openjdk@21 maven google-java-format pmd jq
# Make sure JAVA_HOME points to the installed JDK.
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install openjdk-17-jdk maven jq

# google-java-format (standalone jar)
GJF_VERSION=1.22.0
curl -fsSLO "https://github.com/google/google-java-format/releases/download/v${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar"
echo '#!/bin/sh
exec java -jar /usr/local/lib/google-java-format.jar "$@"' | sudo tee /usr/local/bin/google-java-format > /dev/null
sudo install -m 0644 google-java-format-*.jar /usr/local/lib/google-java-format.jar
sudo chmod +x /usr/local/bin/google-java-format

# PMD
PMD_VERSION=7.6.0
curl -fsSLO "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip"
unzip -q pmd-dist-${PMD_VERSION}-bin.zip -d /opt
sudo ln -sf "/opt/pmd-bin-${PMD_VERSION}/bin/pmd" /usr/local/bin/pmd
```

## Metrics -- what each one measures in Java

### `fmt` -- formatting

Runs `google-java-format --dry-run <file>` on each `.java` under `src/`. Counts files whose `--dry-run` output is non-empty (meaning the file needs to be reformatted).

**Configuration:** `google-java-format` is not configurable by design (single style). Use `--aosp` if the team prefers AOSP style; the current gate does not distinguish.

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `google-java-format -i src/main/java/**/*.java`.

### `lint` -- pmd errorprone

Runs `pmd check --no-cache --no-progress -R category/java/errorprone.xml -d src/main/java -f text`. Counts lines in the format `file.java:line: RuleName: msg`.

The `errorprone` category focuses on real bugs (NPE, broken equals/hashCode, AvoidLiteralsInIfCondition, etc.) and rarely produces noise. For style rules, use `category/java/codestyle.xml` in the `.qg.yaml`/local override.

**Configuration:** if you need additional rules, keep a `pmd-ruleset.xml` file in the project and adjust the gate (or add an extra metric).

**How to interpret a regression:** the PR introduced an issue pmd detects. Fix: read `target/qg-logs/pr-lint.log`, identify the rule, fix the code. `@SuppressWarnings("PMD.RuleName")` only with a documented root cause.

### `build` -- compilation

Runs `mvn -q -B -DskipTests compile`. Counts `[ERROR] /path/Foo.java:[L,C]` lines (the standard compiler format via maven). If the exit code is 0, returns 0 without parsing.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate; usually a merge conflict or an ABI break in a dependency.

### `test` -- failing tests

Runs `mvn -q -B -Dmaven.test.failure.ignore=true test`. Counts `Failures + Errors` from the FINAL SUMMARY ("Tests run: T, Failures: F, Errors: E, Skipped: S"). The gate discards intermediate per-class lines and uses only the last occurrence (total summary).

`-Dmaven.test.failure.ignore=true` is essential so the build does not abort when a test fails (we want the full report).

**Tool error vs regression:** if surefire hangs (OOM, JVM crash), it does not produce a final "Tests run" line -- it does not count as a test failure. These cases are a tool error and the user must investigate.

**How to interpret a regression:** tests that passed now fail. Fix: run `mvn test`, read `target/surefire-reports/`, fix it.

`@Disabled` (JUnit 5) or `@Ignore` (JUnit 4) is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- cyclomatic complexity

Runs `pmd check -R category/java/design.xml/CyclomaticComplexity -d src/main/java`. Counts `CyclomaticComplexity:` matches.

**Threshold:** PMD default is `methodReportLevel=10` for an individual method and `classReportLevel=80` for a class. To customize, keep your own ruleset.

**How to interpret a regression:** the PR introduced a method above the threshold. Fixes: extract private methods; use polymorphism (Strategy pattern) instead of an `if/else` chain; use early-return.

### `coverage` -- line coverage

Runs the `mvn test` that already includes `jacoco:report` (configured in `pom.xml`) and parses `target/site/jacoco/jacoco.xml`. Computes `% covered` from the root counter `<counter type="LINE" missed="M" covered="C"/>`.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**Note:** jacoco counts the default constructor (the class declaration line) as an executable line. For classes that only have `static` methods, this reduces coverage even when all public methods are 100% tested. Consider adjusting the margin in `.qg.yaml` for affected projects.

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test; or (with discretion) raise the margin in `.qg.yaml`.

## Common troubleshooting

### `jacoco.xml` was not generated after `mvn test`

The target project needs `jacoco-maven-plugin` configured with the `report` goal in some phase (`test` recommended). Minimal example:

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.12</version>
  <executions>
    <execution><goals><goal>prepare-agent</goal></goals></execution>
    <execution><id>report</id><phase>test</phase><goals><goal>report</goal></goals></execution>
  </executions>
</plugin>
```

Without this, `coverage` returns 0.

### `mvn` very slow

The Maven caches (`~/.m2/repository`) are not populated. Run `mvn -q -B dependency:resolve` once to download deps; subsequent runs are fast.

### `pmd` exits non-zero but with a confusing message

PMD 7.x changed the CLI. Use `pmd check` (not `pmd-cli check`). If you installed pmd 6.x, update.

### Stale baseline cache after changing the base branch

```bash
~/.claude-plugin/tools/quality-gate/java/qg.sh --base origin/main --refresh-baseline
# OR
rm -rf /tmp/qg-baseline-java
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

None. Java supports the 6 reserved metrics with official tools (google-java-format, pmd, mvn compile/test, jacoco).

## Extra metrics

None in V1. Future candidates:
- `vuln` via `dependency-check-maven` -- vulnerabilities in deps.
- `spotbugs` -- static bugs (partial overlap with pmd; use as a complement).
- `architecture` via `archunit` -- layering rules.

To add, follow the contract (section "Extending") and the maintainer-only `add-quality-gate` skill (project-local, `.claude/skills/add-quality-gate/` in the gate repo).
