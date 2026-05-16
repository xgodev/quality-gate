# Quality Gate -- Kotlin

Documentacao especifica do gate Kotlin. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Kotlin assume **Gradle (`gradle`/`gradlew`) + `build.gradle.kts`** como build canonico em V1. A sentinela detecta `build.gradle` (Groovy DSL) tambem mas o gate so foi testado com Kotlin DSL.

A sentinela de presenca eh `build.gradle.kts` ou `build.gradle` na raiz. Se nenhum existir no baseline, gate emite warning e sai 0.

## Pre-requisitos com instalacao

### macOS

```bash
brew install openjdk@21 gradle ktlint detekt jq
# Garanta que JAVA_HOME aponta para a JDK instalada (ver "brew info openjdk@21").
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install openjdk-21-jdk jq

# Gradle: instale via SDKMAN (apt nativo costuma estar defasado):
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

## Metricas -- o que cada uma mede em Kotlin

### `fmt` -- formatacao

Roda `ktlint 'src/**/*.kt' --reporter=plain`. Conta UMA linha por violacao no formato `file:linha:col: msg`.

**Configuracao:** se o projeto tem `.editorconfig` na raiz, eh respeitado por ktlint. Sem ele, defaults do ktlint ("Kotlin coding conventions" estritas, incluindo function-signature multilinhas).

**Como interpretar regressao:** PR introduziu codigo desformatado. Solucao: `ktlint 'src/**/*.kt' --format` (auto-fix) e revisar o diff.

### `lint` -- detekt

Roda `detekt --input src/main/kotlin --report txt:<log>`. Conta linhas no formato `file:linha:col: ... [RuleName]`.

**Configuracao:** se o projeto tem `detekt.yml` (default name) ou outro arquivo passado via `--config`, eh respeitado. Sem config, defaults do detekt (regras "default" sem opt-ins).

**Como interpretar regressao:** PR introduziu issue que detekt detecta. Solucao: ler `target/qg-logs/pr-lint.log`, identificar regra, fixar codigo. `@Suppress("RuleName")` so com causa raiz documentada.

### `build` -- compilacao

Roda `gradle compileKotlin -q --no-daemon`. Conta linhas `file.kt:linha:col: error:` se exit code != 0.

**Como interpretar regressao:** codigo nao compila. Pouco provavel passar pelo dev e chegar no gate.

### `test` -- testes falhando

Roda `gradle test --rerun-tasks --no-daemon`. Conta o numero N do resumo `N tests completed, F failed` (gradle imprime essa linha por modulo de teste; o gate pega a UTLIMA ocorrencia).

`--rerun-tasks` eh ESSENCIAL: sem ele, gradle marca o task `:test` como `UP-TO-DATE` entre execucoes consecutivas e nao re-executa, retornando 0 mesmo quando ha testes falhando. O `build.gradle.kts` do projeto deve ter `tasks.test { ignoreFailures = true }` para nao abortar a build.

**Tool error vs regressao:** se gradle trava (OOM, JVM crash), nao gera linha "tests completed" -- nao conta como falha de teste. Esses casos sao tool error e o usuario precisa investigar.

**Como interpretar regressao:** testes que passavam falham agora. Solucao: rodar `gradle test --info`, ler erro, fixar.

`@Ignore` (JUnit 4) ou `@Disabled` (JUnit 5) eh proibido como mitigacao (ver [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- complexidade

Roda o mesmo `detekt` que o `lint`, mas conta apenas matches das regras especificas:

- `CyclomaticComplexMethod` (default threshold = 15)
- `ComplexCondition` (default threshold = 4 expressoes booleanas)
- `NestedBlockDepth` (default threshold = 4)
- `LongMethod` (default threshold = 60 linhas)
- `LongParameterList` (default threshold = 6 parametros funcao)

**Como interpretar regressao:** PR introduziu funcao acima de algum threshold. Solucoes: extrair sub-funcoes; substituir cadeias `if/else` por `when` ou polimorfismo; usar early-return.

### `coverage` -- cobertura de linhas

Roda `gradle koverXmlReport --no-daemon` e parsea `build/reports/kover/report.xml`. Calcula `% covered` do contador raiz `<counter type="LINE" missed="M" covered="C"/>`.

Kover usa o mesmo formato XML do JaCoCo. O projeto-alvo precisa ter `kover` plugin aplicado: `id("org.jetbrains.kotlinx.kover") version "0.8.3"` em `plugins{}`.

**Margem de tolerancia:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Como interpretar regressao:** PR adicionou codigo sem teste correspondente. Solucoes: adicionar teste; ou (com criterio) aumentar margem em `.qg.yaml`.

## Troubleshooting comum

### `Cannot find a Java installation matching: {languageVersion=17, ...}`

Gradle nao encontra a JDK na versao requerida no `jvmToolchain(N)` do `build.gradle.kts`. Solucao: ajuste `jvmToolchain` para a versao instalada (`jvmToolchain(21)` se voce tem JDK 21) OU instale a JDK requerida e setar `JAVA_HOME`.

### `gradle test` reporta 0 falhas mesmo com teste falhando

Gradle cacheia o output do task `:test` como `UP-TO-DATE`. O gate ja usa `--rerun-tasks` mas se voce rodar `gradle test` manualmente sem essa flag, vai bater no cache. Solucao: sempre `gradle test --rerun-tasks` ou `gradle clean test`.

### `kover` plugin nao aplicado, coverage retorna 0

O projeto-alvo precisa ter:

```kotlin
plugins {
    id("org.jetbrains.kotlinx.kover") version "0.8.3"
}
```

E o report XML eh gerado em `build/reports/kover/report.xml` apos `gradle koverXmlReport`.

### Baseline cache stale apos mudar branch base

```bash
~/.quality-gate/kotlin/qg.sh --base origin/main --refresh-baseline
# OU
rm -rf /tmp/qg-baseline-kotlin
```

### `git archive` falha com "fatal: not a valid object name"

A base ref nao existe localmente. Solucao:

```bash
git fetch origin
```

## Metricas omitidas

Nenhuma. Kotlin suporta as 6 metricas reservadas com ferramentas oficiais (ktlint, detekt, gradle compileKotlin/test, kover).

## Metricas extras

Nenhuma em V1. Candidatos futuros:
- `vuln` via `gradle dependencyCheckAnalyze` (OWASP Dependency-Check) -- vulnerabilidades em deps.
- `binary_compat` via `kotlinx-binary-compatibility-validator` -- breaking changes na API.
- `unused_deps` via `gradle nebula.dependency-lock` ou similar.

Para adicionar, seguir contrato (secao "Estender") e `.claude/skills/add-quality-gate/`.
