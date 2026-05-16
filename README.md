# Quality Gate

Gate de qualidade compartilhado entre projetos. Roda **igual** local e em CI: falha **somente** quando o PR piora alguma métrica em relação a uma base ref escolhida.

## Como funciona

1. Cada linguagem suportada tem um script standalone em `<lang>/qg.sh` (ex: `rust/qg.sh`).
2. O script compara métricas (fmt, lint, build, test, complexity, coverage) entre o estado atual e a base ref passada via `--base`.
3. Dívida preexistente nunca bloqueia. Só piora bloqueia.

### Dispatcher `qg` (ponto de entrada)

O jeito canonico de rodar e o **dispatcher `qg` na raiz**:

```bash
cd /caminho/do/seu/projeto
~/.quality-gate/qg --base origin/main          # roda o(s) gate(s)
~/.quality-gate/qg --detect                    # lista linguagens
```

Deteccao 100% shell (zero IA): o `qg` faz `<lang>/qg.sh --detect` para
descobrir a(s) linguagem(s) e roda o(s) gate(s) correspondente(s). Repassa
todas as flags. **Monorepo:** `.qg.yaml` com bloco `projects:` lista os
sub-projetos. Exit codes: `0` verde, `1` regressao/threshold, `2`
tool/setup, **`3` nenhuma linguagem suportada detectada** (exclusivo do
dispatcher). Veredito agregado de N gates = pior (precedencia `2 > 1 > 3 > 0`);
em `--format json` emite `{aggregate_verdict, results:[...]}`.

### Modo absoluto e `--detect` (contrato v1.1)

- **`--detect`**: `<lang>/qg.sh --detect` imprime o slug da linguagem + exit 0 se a sentinela existe na raiz do projeto, ou exit 1 se não. Curto-circuita tudo. O dispatcher usa isto para descobrir quais gates rodar sem tabela hardcoded.
- **Modo absoluto**: rodar `<lang>/qg.sh` (ou `qg`) **sem** `--base` (e sem `QG_BASE_REF`) mede o estado atual uma vez, sem baseline. Exit 0 sempre, exceto se `.qg.yaml` definir `absolute_thresholds` e alguma métrica violar um limite (exit 1). Útil quando não há base ref (ex: legado sem PR de referência). JSON traz `mode: "absolute"`, `base_ref: null`, `schema_version: "1.1"`.

O modo comparativo (com `--base`) não muda — v1.1 é aditivo e backward-compatible.

### Tamper-resistance

O gate **traz e impoe os proprios rulesets** (`<lang>/rules/`). Configs de
qualidade do projeto-alvo (`.eslintrc`, `clippy.toml`, `.stylelintrc`,
etc.) são **ignoradas por padrao** — senao o dev afrouxa uma regra no
proprio repo e o gate vira teatro. Override só via env externa
`QG_RULESET_DIR` (quem RODA o gate), nunca de `.qg.yaml`/arquivo do projeto.

### React / Vue / Svelte / Angular = projeto nodejs

Projeto com `package.json` (mesmo React/Vue/etc.) e coberto por
`nodejs/qg.sh`. O gate `web` so cobre **HTML/CSS estatico puro** (sem
`package.json`). Regras de framework entram no ruleset do QG
(`nodejs/rules/`), nunca no config do projeto.

## Linguagens suportadas

| Linguagem | Script | Métricas medidas | Pré-reqs |
|---|---|---|---|
| Rust | [`rust/qg.sh`](rust/README.md) | fmt, lint, build, test, complexity, coverage | cargo, cargo-llvm-cov, jq |
| Go | [`go/qg.sh`](go/README.md) | fmt, lint, build, test, complexity, coverage | go, gofmt, gocyclo, golangci-lint (opcional), jq |
| Python | [`python/qg.sh`](python/README.md) | fmt, lint, build, test, complexity, coverage | python3, ruff, pytest, pytest-cov, radon, jq |
| Node.js | [`nodejs/qg.sh`](nodejs/README.md) | fmt, lint, build, test, complexity, coverage | node 18+, npm, npx, jq (prettier/eslint/c8 via npx) |
| Java | [`java/qg.sh`](java/README.md) | fmt, lint, build, test, complexity, coverage | java 17+, mvn, google-java-format, pmd, jq (jacoco-plugin no projeto) |
| Swift\* | [`swift/qg.sh`](swift/README.md) | fmt, lint, build, test, coverage | swift 5.9+, swift-format, swiftlint, jq (xcrun no macOS) |
| Kotlin | [`kotlin/qg.sh`](kotlin/README.md) | fmt, lint, build, test, complexity, coverage | java 17+, gradle, ktlint, detekt, jq (kover plugin no projeto) |
| Web (HTML/CSS)\* | [`web/qg.sh`](web/README.md) | fmt, lint | node 18+, jq (prettier/stylelint/htmlhint via npx) |

\* `complexity` omitido em Swift -- ver [`docs/languages/swift.md`](docs/languages/swift.md) seção "Metricas omitidas". `build`, `test`, `complexity` e `coverage` omitidos em Web (HTML/CSS estatico nao tem build/test/complexidade/cobertura) -- ver [`docs/languages/web.md`](docs/languages/web.md). Projeto React/Vue/etc. com `package.json` = projeto **nodejs** (`nodejs/qg.sh`), nao web.

## Quick start

```bash
# Clone uma vez
git clone git@github.com:xgodev/quality-gate.git ~/.quality-gate

# Rode no seu projeto (dispatcher detecta a linguagem sozinho)
cd /caminho/do/seu/projeto
~/.quality-gate/qg --base origin/main
```

## Documentação

- [`docs/contract.md`](docs/contract.md) — contrato comum a toda linguagem (CLI, exit codes, output, bypass, `.qg.yaml`).
- [`docs/output-format.md`](docs/output-format.md) — formatos texto e JSON detalhados.
- [`docs/consume.md`](docs/consume.md) — como integrar no seu projeto (local agora; CI em V2).
- [`docs/languages/rust.md`](docs/languages/rust.md) — pré-reqs, métricas e troubleshooting de Rust.
- [`docs/languages/go.md`](docs/languages/go.md) — pré-reqs, métricas e troubleshooting de Go.
- [`docs/languages/python.md`](docs/languages/python.md) — pré-reqs, métricas e troubleshooting de Python.
- [`docs/languages/nodejs.md`](docs/languages/nodejs.md) — pré-reqs, métricas e troubleshooting de Node.js.
- [`docs/languages/java.md`](docs/languages/java.md) — pré-reqs, métricas e troubleshooting de Java.
- [`docs/languages/swift.md`](docs/languages/swift.md) — pré-reqs, métricas e troubleshooting de Swift (complexity omitido).
- [`docs/languages/kotlin.md`](docs/languages/kotlin.md) — pré-reqs, métricas e troubleshooting de Kotlin.
- [`docs/languages/web.md`](docs/languages/web.md) — pré-reqs e troubleshooting de Web (HTML/CSS; só fmt+lint; React/Vue=nodejs).

## Contribuindo

Veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Para adicionar nova linguagem com auxílio de IA, use a skill `add-quality-gate` em `.claude/skills/`.
