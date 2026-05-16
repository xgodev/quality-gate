# Contrato do Quality Gate (v1)

Versão do contrato: **1.x** (`QG_CONTRACT_VERSION=1`). `schema_version` do JSON: `1.1`.

Este documento define o que **todo** `<lang>/qg.sh` precisa cumprir. Mudanças aqui exigem atualização de TODOS os scripts existentes.

A v1.1 é **aditiva e backward-compatible**: o modo comparativo (com `--base`) não muda. As adições são `--detect`, modo absoluto (`--base` opcional), bloco `.qg.yaml absolute_thresholds`, campo `mode` no JSON e enum de veredito consolidado. `QG_CONTRACT_VERSION` continua `1`.

## CLI

```
<lang>/qg.sh [--base <git-ref>] [opções]
<lang>/qg.sh --detect

Opções:
  --detect              Curto-circuita: detecta se a linguagem existe na raiz
                        do projeto. Imprime o slug + exit 0 se sim, exit 1 se nao.
  --base <ref>          Ref a comparar (ex: origin/main, develop). Se ausente
                        (e sem QG_BASE_REF), o gate roda em MODO ABSOLUTO.
  --baseline-dir <dir>  Path de baseline já preparado. Pula extração via git archive.
  --cov-margin <pp>     Tolerância de coverage em pp (decimal). Default: 1.0
  --log-dir <dir>       Onde gravar logs por etapa. Default: target/qg-logs
  --refresh-baseline    Re-extrai baseline mesmo se cache existir.
  --force-full          Pula fast-path; mede tudo mesmo se nada mudou.
  --format text|json    Formato de output em stdout. Default: text.
  -h, --help            Mostra ajuda.
```

## `--detect`

`<lang>/qg.sh --detect` curto-circuita ANTES de qualquer outra validação (é a primeira coisa após o parse de args, antes do check de `--base`/`--format`/pré-requisitos):

- Verifica se a sentinela da linguagem existe na raiz do projeto (`git rev-parse --show-toplevel 2>/dev/null || pwd`).
- Sentinela presente → imprime o slug da linguagem em stdout (ex: `rust`) e **exit 0**.
- Ausente → nada em stdout, **exit 1**.
- Reusa a MESMA sentinela usada no check de "linguagem ausente no baseline" / fast-path. Não duplica regex.

Sentinelas reservadas por linguagem:

| Linguagem | Sentinela |
|---|---|
| rust | `Cargo.toml` |
| go | `go.mod` |
| python | `pyproject.toml` ou `setup.py` ou `setup.cfg` ou `requirements*.txt` |
| nodejs | `package.json` |
| java | `pom.xml` ou `build.gradle` ou `build.gradle.kts` |
| swift | `Package.swift` |
| kotlin | `build.gradle.kts` ou `settings.gradle.kts` ou `build.gradle` |

Consumidores (skill `quality-gate`) iteram `<lang>/qg.sh --detect`, coletam os que saem 0 e rodam só esses — sem tabela hardcoded de sentinelas.

## Modo absoluto (`--base` opcional)

Se `--base` E `QG_BASE_REF` ambos ausentes → **modo absoluto** (não é erro; não sai 2).

- **Pula** provisão de baseline inteiramente (sem `git archive`, sem `--baseline-dir`).
- **Pula** fast-path (sem base não há diff — sempre mede full).
- **Pula** check de "linguagem ausente no baseline" (não há baseline).
- Roda as funções de medição **uma vez**, em `.`.
- Pass/fail: **exit 0 SEMPRE**, exceto se `.qg.yaml` definir `absolute_thresholds` e alguma métrica medida violar um → **exit 1**.

`absolute_thresholds` é ignorado em modo comparativo (lá quem manda é a comparação base/PR + `cov_margin`).

## Exit codes

| Code | Significado |
|---|---|
| 0 | Sem regressão / sem violação (PASS, fast-path, bypassed, modo absoluto sem violação ou `--detect` com sentinela) |
| 1 | Modo comparativo: ≥1 métrica regrediu. Modo absoluto: ≥1 `absolute_thresholds` violado. `--detect`: sentinela ausente |
| 2 | Erro de setup: ferramenta faltando, baseline inválido, `.qg.yaml` inválido, ferramenta de medição quebrou, falha ao resolver dependências |

`--base` ausente NÃO é mais exit 2 — vira modo absoluto. `--detect` usa exit 1 só para "sentinela ausente" (nunca exit 2).

**Tool error ≠ regressão.** Segfault de compilador → exit 2, não exit 1. Falha ao resolver dependências (rede, lockfile corrompido, registry privado sem auth) → exit 2, **nunca** `build` regredido.

## Variáveis de ambiente

| Nome | Default | Uso |
|---|---|---|
| `QG_BYPASS_REASON` | (vazio) | Setada → gate sai 0 + audit log. Ver seção Bypass. |
| `QG_LOG_DIR` | `target/qg-logs` | Equivalente a `--log-dir`. CLI tem precedência. |
| `QG_BASE_REF` | (vazio) | Equivalente a `--base`. CLI tem precedência. Vazio + sem `--base` → modo absoluto. |
| `QG_BASELINE_DIR` | (vazio) | Equivalente a `--baseline-dir`. CLI tem precedência. |
| `QG_COV_MARGIN` | `1.0` | Equivalente a `--cov-margin`. CLI tem precedência. |
| `QG_REFRESH_BASELINE` | `0` | `1` equivalente a `--refresh-baseline`. |
| `QG_FORCE_FULL` | `0` | `1` equivalente a `--force-full`. |
| `QG_FORMAT` | `text` | Equivalente a `--format`. |
| `QG_RULESET_DIR` | (vazio) | Override do `rules/` embarcado (tamper-resistance). So honrado se vier do AMBIENTE de quem roda o gate — NUNCA de `.qg.yaml`/arquivo do projeto. Vazio → usa `<QG>/<lang>/rules/`. |

## Output texto (default)

Estrutura fixa em 3 blocos:

```
═══ Quality Gate — <lang> ═══
  branch:        <branch atual>
  base ref:      <--base>
  baseline:      <path>
  cov margin:    <pp>pp
  logs:          <dir>/

── medindo base ──
[silencioso; logs em <log-dir>/base-*.log]

── medindo PR ──
[silencioso; logs em <log-dir>/pr-*.log]

métrica       base       pr     veredito
─────────────────────────────────────────
fmt              0        0    ✅ same
lint             3        2    ✅ improved
build            0        0    ✅ same
test fails       0        1    ❌ regressed
complexity       7        7    ✅ same
coverage     82.3%    81.0%   ❌ regressed (margem: 1.0pp)

::error::PR regrediu test fails, coverage — ver acima.
```

Output em **PT-BR**. Identificadores (`improved`, `same`, `regressed`) em EN ASCII.

## Output JSON (`--format json`)

Stdout recebe SOMENTE o JSON. Mensagens de progresso vão para stderr; logs detalhados continuam em `--log-dir`.

Schema validado contra [`contract-v1.schema.json`](contract-v1.schema.json) (aceita `schema_version` `"1.0"` e `"1.1"`).

Campo top-level **`"mode"`**: `"comparative"` | `"absolute"`. Ausente ⇒ tratar como `comparative` legacy 1.0.

### Modo comparativo

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

`base_ref` continua string. Métricas continuam `{name, base, pr, delta, verdict}`.

### Modo absoluto

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
- Cada métrica: `{ "name", "value", "threshold" (number|null), "verdict" }`.
  - `verdict` por métrica ∈ `"ok"` (threshold definido, não violado) | `"violated"` (threshold violado) | `"reported"` (sem threshold — informativo).
- `verdict` global ∈ `passed|failed|bypassed`. `failed` = ≥1 métrica `violated`. Sem violação (ou nenhum threshold) → `passed`.

### Enum de veredito consolidado

`verdict` global do schema v1.1: **`passed | regressed | failed | bypassed`**.
- `regressed` só em modo comparativo.
- `failed` só em modo absoluto.
- `passed`/`bypassed` ambos os modos.

Métrica `verdict`: comparativo usa `same|improved|regressed`; absoluto usa `ok|violated|reported`. O schema discrimina via `if mode`.

Regras gerais:

- Métrica omitida pela linguagem **não aparece** na lista.
- Métrica extra (além das 6) aparece com mesmo schema.

## Bypass governado

Env var `QG_BYPASS_REASON="<motivo>"`:

- Setada e não-vazia: gate **sempre** sai 0.
  - Texto: bloco `::warning::QG bypass ativo — motivo: <motivo>` + linha `::warning::Esta execução não validou métricas. Audit log: <path>`.
  - JSON: `verdict: "bypassed"`, `bypass_reason: "<motivo>"`, `metrics: []`.
- Vazia/não-setada: comportamento normal.

**Audit log:** `<log-dir>/bypass.log` com timestamp UTC, branch, usuário (`git config user.email`), motivo. V2 centraliza.

Sem flag CLI equivalente. Env var fricciona deliberadamente.

## Dispatcher deterministico (`qg` na raiz)

A raiz do repo do gate traz um executavel `qg` (`~/.quality-gate/qg`).
Detecção **100% shell, zero IA**: descobre a(s) linguagem(s) do projeto-alvo via
`<lang>/qg.sh --detect` e roda o(s) gate(s) correspondente(s). A skill consumer
SO chama este script — nunca itera `<lang>/qg.sh` por conta propria nem mantem
tabela hardcoded de sentinelas.

- **Descoberta de sub-projetos (hibrido):**
  - Se existe `<target>/.qg.yaml` com bloco `projects:` → usa APENAS essa lista.
    Cada item: `path:` obrigatorio, `lang:` opcional. Para cada `path`, roda
    `<lang>/qg.sh --detect` dentro de `<target>/<path>` (se `lang:` dado, so
    testa esse; senao testa todos).
  - Senao → detecção na raiz: para cada `<root>/*/qg.sh`, roda
    `(cd <target> && <s> --detect)`. Coleta os que saem 0.
- **Execução:**
  - 0 matches → stderr `::error::nenhuma linguagem suportada detectada`, **exit 3**
    (codigo determinístico reservado para "nenhuma linguagem").
  - 1 match → roda `<lang>/qg.sh "$@"` no diretorio certo, repassa exit code.
  - N matches → roda todos sequencialmente. **Veredito global = pior**: qualquer
    exit != 0 → exit != 0 (precedencia: `2 > 1 > 3 > 0`). Em `--format json`,
    emite um array `[{lang,...}, ...]` com campo top-level `aggregate_verdict`.
- Repassa flags (`--base`, `--format`, `--cov-margin`, `--log-dir`, etc.)
  intactas para o(s) `<lang>/qg.sh`.
- `qg --detect` → lista os slugs detectados (um por linha), exit 0 se >= 1,
  exit 3 se 0.

### Exit code 3 reservado

| Code | Significado |
|---|---|
| 3 | **Dispatcher:** nenhuma linguagem suportada detectada no projeto-alvo |

Exit 3 e do **dispatcher**, nunca de um `<lang>/qg.sh` individual. Consumidores
mapeiam: 3 → "linguagem fora do escopo", 2 → tool/setup error, 1 → regressao/
threshold violado, 0 → verde.

## React/Vue/etc. NAO viram gate proprio

Projeto React, Vue, Svelte, Angular, etc. = **projeto nodejs**, coberto por
`nodejs/qg.sh` (sentinela `package.json`). Regras especificas de framework entram
no **ruleset do QG** (ver "Tamper-resistance"), nunca em config do projeto-alvo.
O gate `web` so cobre HTML/CSS **estatico puro** (sem `package.json`).

## Tamper-resistance — o ruleset e do QG (LEI, todas as linguagens)

**LEI:** o gate **traz e impoe os proprios rulesets**. Configs de qualidade do
projeto-alvo (`.eslintrc`, `clippy.toml`, `pyproject.toml [tool.ruff]`,
`.swiftlint.yml`, `detekt.yml`, `.stylelintrc`, etc.) sao **ignoradas por
padrao**. Senao o dev afrouxa uma regra no proprio repo e o gate vira teatro.

- Cada `<lang>/` embarca um diretorio `rules/` com a config canonica.
- `<lang>/qg.sh` (via `lib/measure.sh`) invoca a ferramenta apontando para o
  `rules/` do QG **e com as flags que ignoram config local**:

| Linguagem | Como o QG forca o proprio ruleset |
|---|---|
| rust | `CLIPPY_CONF_DIR=<QG>/rust/rules`; `cargo fmt -- --config-path <QG>/rust/rules/rustfmt.toml` |
| go | `golangci-lint run -c <QG>/go/rules/.golangci.yml`; `gocyclo` threshold fixo no script. `gofmt` nao tem config → trivialmente tamper-proof |
| python | `ruff --config <QG>/python/rules/ruff.toml` (`--config` arquivo explicito faz ruff ignorar pyproject/ruff.toml do projeto); `radon` threshold fixo no script |
| nodejs | `eslint --no-config-lookup --config <QG>/nodejs/rules/eslint.config.mjs`; `prettier --config <QG>/nodejs/rules/.prettierrc.json --no-editorconfig`; `tsc -p <efemero>` que faz `extends` de `<QG>/nodejs/rules/tsconfig.base.json` (strict travado, independente do tsconfig do projeto). O `tsconfig.base.json` do QG e strict porem JSX/React-Native-capaz (`jsx: preserve` + shim `qg-jsx-shim.d.ts`): parseia `.tsx` sem TS17004/TS7026 fantasma, mas o dev NAO afrouxa strictness (regra de tamper continua: ruleset do QG manda) |
| java | `pmd -R <QG>/java/rules/pmd.xml`; `google-java-format` (estilo fixo, sem config) |
| swift | `swiftlint --config <QG>/swift/rules/.swiftlint.yml`; `swift-format --configuration <QG>/swift/rules/.swift-format` |
| kotlin | `detekt -c <QG>/kotlin/rules/detekt.yml`; `ktlint --editorconfig=<QG>/kotlin/rules/.editorconfig` |
| web | `stylelint --config <QG>/web/rules/.stylelintrc.json` (arquivo explicito sobrepoe .stylelintrc do projeto); `htmlhint --config <QG>/web/rules/.htmlhintrc`; `prettier --config <QG>/web/rules/.prettierrc.json --no-editorconfig` |

- **Override so externo:** ruleset alternativo so via env `QG_RULESET_DIR=<path>`
  setada por quem **roda** o gate (pipeline / dev consciente). **NUNCA** lido de
  arquivo do projeto-alvo (nem de `.qg.yaml`, que o dev controla). Default
  sempre = `rules/` do QG embarcado.
- Conteudo dos `rules/`: defaults da comunidade (clippy 25/100/7/250, eslint
  recommended + prettier, ruff default, etc.). Calibracao fina e V2 — o que o
  contrato garante e a **mecanica** de nao ler config do projeto.

### LEI: fmt/lint/complexity medem CODIGO-FONTE (ignore canonico do QG)

**LEI:** as metricas `fmt`/`lint`/`complexity` medem **CODIGO-FONTE**.
Diretorios **gerados/vendored** sao excluidos por um **ignore CANONICO
proprio do QG** (tamper-proof: **NUNCA** lido de `.eslintignore` /
`.prettierignore` / `.gitignore` / `.qg.yaml` do projeto-alvo — o dev nao
afrouxa a varredura). Medir artefato (bundle minificado em `build/`, dep em
`vendor/`) infla o numero e torna a metrica inutil.

Lista canonica de exclusao (dirs gerados/vendored): `node_modules/`,
`dist/`, `build/`, `out/`, `.next/`, `.nuxt/`, `.expo/`, `coverage/`,
`.turbo/`, `.cache/` (+ `.venv/`/`venv/` em Python, `vendor/` em Go) e
arquivos `*.min.js`, `*.min.css`, `*.bundle.js`, `*.chunk.js`, `*-lock.json`,
`*.map`. Aplicada em TODA medicao que varre arquivos por path:

| Linguagem | Mecanismo do ignore canonico |
|---|---|
| nodejs | bloco `ignores` (1o elemento, ignore global) no `eslint.config.mjs` do QG (lint+complexity); `prettier --ignore-path <QG>/nodejs/rules/.prettierignore` (fmt); `_qg_node_sources` exclui os dirs (build) |
| web | `prettier --ignore-path <QG>/web/rules/.prettierignore`; `_qg_web_css`/`_qg_web_html` prune da lista canonica + lista explicita p/ stylelint/htmlhint |
| python | `extend-exclude` no `ruff.toml` do QG (independe de respect-gitignore); `radon -i/-e` com a lista canonica |
| go | `gofmt -l`/`gocyclo` filtrados pela lista canonica (vendor/ classico); `./...` ja e module-scoped |
| rust/java/kotlin/swift | sem anti-pattern: cargo/mvn-pmd/ktlint-detekt sao scope de crate/`src/`; swift exclui `.build/` |

Override **so externo** (`QG_RULESET_DIR`), nunca de arquivo do projeto —
mesma regra de tamper do ruleset.

## Config por repo (`.qg.yaml` opcional)

Lido da raiz do projeto-alvo se existir. Schema **fechado** — chave desconhecida → exit 2.

```yaml
cov_margin: 2.0                       # override do default 1.0
skip_metrics:
  - metric: complexity
    reason: "legacy crate, plano em INT-1234"
    until: "2026-09-01"               # ISO 8601
extra_fast_path_paths:
  - "^vendor/"
  - "^third_party/"
projects:                             # monorepo: lista fechada de sub-projetos
  - path: backend
    lang: go
  - path: frontend                    # lang omitido -> dispatcher detecta
```

### Bloco `projects` (monorepo)

Lido APENAS pelo dispatcher `qg` da raiz. Schema **fechado** por item: chaves
permitidas = `path` (obrigatorio), `lang` (opcional). Chave desconhecida → exit 2.
Se `projects:` existe, o dispatcher **ignora** a detecção na raiz e usa so esta
lista. `lang:` NAO seleciona ruleset (isso e tamper-surface) — so restringe qual
`<lang>/qg.sh --detect` testar dentro do `path`.

Schema fechado total do `.qg.yaml`: `cov_margin`, `skip_metrics`,
`extra_fast_path_paths`, `absolute_thresholds`, `projects`.

Regras:

- `until` no passado → script ignora skip e volta a medir/bloquear (registra `::warning::skip de <metric> expirou em <data>`).
- `skip_metrics` sem `reason` ou sem `until` → exit 2.
- Mesmo schema vale para TODA linguagem.

### Bloco `absolute_thresholds` (modo absoluto)

Bloco opcional, lido APENAS em modo absoluto:

```yaml
absolute_thresholds:
  fmt: 0
  lint: 0
  build: 0
  test: 0
  complexity: 10
  coverage: 80      # MINIMO (coverage = maior é melhor)
```

- Schema fechado: chaves permitidas sob `absolute_thresholds` = os 6 nomes reservados + qualquer métrica extra que a linguagem declare. Chave desconhecida → exit 2.
- Contadores (`fmt`/`lint`/`build`/`test`/`complexity` e extras-contador): violação se `valor > threshold`.
- `coverage` (e extras percentuais): violação se `valor < threshold` (é um mínimo).
- Qualquer violação → **exit 1**. Nenhum threshold definido, ou sem `.qg.yaml`, ou sem bloco `absolute_thresholds` → **exit 0**, só reporta (`verdict: reported`).
- Ignorado em modo comparativo.

## Métricas reservadas

Estes 6 nomes são reservados — se a linguagem mede a métrica, **usa esse nome exato**:

| Nome | Conta | Falha se |
|---|---|---|
| `fmt` | arquivos não-formatados | PR > base |
| `lint` | erros do linter | PR > base |
| `build` | erros de build | PR > base |
| `test` | testes que falharam | PR > base |
| `complexity` | violações de complexidade | PR > base |
| `coverage` | % linhas cobertas | PR < base − margem |

**Omitir:** linguagem documenta em `docs/languages/<lang>.md` por que não tem ferramenta. Não imprime linha no texto, omite no JSON.

**Estender:** métrica extra com nome snake_case ASCII único, mesma regra de regressão.

## Fast-path

Cada `<lang>/qg.sh` define regex de "arquivos-fonte da linguagem":

- Rust: `\.rs$|^Cargo\.|build\.rs$|^rust-toolchain`

Se `git diff --name-only <base>...HEAD` (+ staged + worktree) não casar nada e `--force-full` não passou:
1. Imprime header de fast-path (texto) ou `verdict: "passed"` com `metrics: []` (JSON).
2. Valida sintaxe de scripts shell modificados (`bash -n`).
3. Exit 0.

`extra_fast_path_paths` do `.qg.yaml` é adicionado ao regex.

## Baseline

- Sem `--baseline-dir`: `git archive <base>` em `/tmp/qg-baseline-<lang>` (cacheado; `--refresh-baseline` força re-extração).
- Com `--baseline-dir`: assume diretório pronto (CI fez checkout em path separado).
- Linguagem ausente no baseline (ex: PR adiciona `Cargo.toml` pela 1ª vez): `::warning::linguagem ausente no baseline — gate skipped` + exit 0.

## Pré-requisitos por linguagem

Cada `<lang>/qg.sh` valida ferramentas no início. Faltando: exit 2 com mensagem clara.

### LEI: toda mensagem de ferramenta ausente ensina a instalar (Linux + macOS)

**LEI:** TODA mensagem `::error::` de ferramenta / gerenciador / build-system /
toolchain **ausente ou não encontrada** DEVE incluir o comando de instalação
para **Linux E macOS** e a consequência de ignorar. Vale para:

- entradas de `check_prereqs` (o array `missing+=(...)` de cada `<lang>/qg.sh`);
- erros de manager/build-system/toolchain ausente em `<lang>/lib/*.sh` (ex:
  `yarn.lock` + `yarn` ausente, `poetry.lock` + `poetry` ausente, `pom.xml`
  sem Maven, channel pinado em `rust-toolchain` não instalado).

Formato canônico (ASCII, `--` nunca em-dash):

```
::error::<causa> -- instale: '<cmd linux>' (Linux) / '<cmd macOS>' (macOS) (<consequencia se ignorar>)
```

Exemplos: `yarn` → `npm i -g yarn` / `brew install yarn`; `pnpm` →
`npm i -g pnpm` / `brew install pnpm`; `poetry` → `pipx install poetry` /
`brew install poetry`; `cargo-llvm-cov` → `cargo install cargo-llvm-cov`
(ambos); `jq` → `apt install jq` / `brew install jq`. Se o tool não é
trivialmente instalável (ex: build-system não suportado pelo gate), a ação
correta substitui o `instale:` (`abra issue / add-quality-gate`), mas a
mensagem continua acionável.

Comuns: `git`, `bash 4+`, `awk`, `tar`, `jq`.

## Compatibilidade GNU/BSD

Scripts rodam em macOS dev (BSD) e Linux CI (GNU). Regras:

- Sem `sed -i` — usar `sed -e ... > tmp && mv tmp arquivo`.
- Sem `grep -P` (não está em BSD).
- Sem `awk gensub` — usar `gsub`.
- Sem `find -regex` — usar `find ... | grep -E`.

## Resolução de dependências antes de build/test (obrigatório)

Antes de medir `build`/`test`/`coverage`, o script DEVE resolver o closure de dependências do diretório medido (tanto PR quanto baseline em modo comparativo; o diretório atual em modo absoluto). Medir build sem `node_modules`/venv/etc resolvido produz falso `build` regredido.

| Linguagem | Resolução de deps antes de build/test |
|---|---|
| nodejs | detectar lockfile: `pnpm-lock.yaml`→`pnpm i --frozen-lockfile`; `yarn.lock`→`yarn install --immutable` se `.yarnrc.yml` presente (Yarn Berry v2+), senão `yarn install --frozen-lockfile` (Yarn classic v1); senão `npm ci` (fallback `npm install` se não há `package-lock.json`). Só se `node_modules/` ausente ou lockfile mais novo. |
| python | se há `requirements*.txt`/`pyproject.toml` e não há venv ativa com deps: criar venv efêmera e `pip install -q -r ...` / `pip install -q .`. |
| java | `mvn` resolve no `compile`/`test`; garantir `-o` (offline) NÃO usado; se resolução falha → tool-error. |
| kotlin | `gradle` resolve sozinho; garantir não-offline; se resolução falha → tool-error. |
| go | `go build`/`go test` resolvem via go modules; garantir `GOFLAGS=-mod=mod`; se download falha → tool-error. |
| rust | `cargo` resolve sozinho. Sem mudança. |
| swift | `swift build` resolve SwiftPM. Sem mudança. |

### Toolchain/build-system declarado é autoritativo (LEI)

O gate mede o que o projeto **realmente usa**. Se o projeto declara um gerenciador de dependências, build-system ou toolchain específico e o gate **não consegue honrá-lo exatamente** (ferramenta ausente no PATH, versão pinada não satisfazível, build-system não suportado pelo gate da linguagem), isso é **tool-error → exit 2** com mensagem clara no log apontando a causa. **NUNCA** substituir silenciosamente por outra ferramenta/versão/manager que produziria resultado diferente.

Substituição silenciosa mascara a causa real com erro enganoso e mede um artefato que não corresponde ao que CI/produção vão construir → veredito sem valor. Generaliza a LEI nodejs (`025d8e0`) para todas as linguagens.

Não-objetivo: o gate **não** passa a implementar todo build-system. Build-system não suportado = tool-error honesto (instrução: abrir issue / `add-quality-gate`), não substituição.

| Linguagem | Anti-pattern a corrigir | Comportamento correto |
|---|---|---|
| **nodejs** | (FEITO em `025d8e0`) lockfile + manager ausente → fallback npm | lockfile autoritativo; manager ausente = tool-error |
| **java** | `build.gradle`/`build.gradle.kts` (Gradle) presente mas gate roda `mvn` silenciosamente | `pom.xml`→Maven (suportado). Gradle (sem `pom.xml`)→ tool-error: "gate Java suporta apenas Maven hoje — abra issue / add-quality-gate". Se `./mvnw` presente, usar o wrapper (versão pinada), não `mvn` do sistema. |
| **python** | `poetry.lock`/`pdm.lock`/`uv.lock`/`Pipfile.lock` presente mas gate usa `pip install` (resolver diferente) | Detectar manager pelo lockfile: `poetry.lock`→poetry; `pdm.lock`→pdm; `uv.lock`→uv; `Pipfile.lock`→pipenv; só `requirements*.txt`/`pyproject` sem lock→pip. Manager do lock ausente = tool-error, nunca pip. |
| **kotlin** | `gradle` do sistema usado ignorando `./gradlew` (versão pinada no wrapper) | Se `./gradlew` presente, usar o wrapper; erro do wrapper que force `gradle` do sistema de versão diferente = tool-error, não substituição. |
| **go** | `go.mod` com diretiva `toolchain`/`go 1.x` não satisfeita pelo `go` do PATH; build com versão diferente | Respeitar `GOTOOLCHAIN` (default `auto` baixa a pinada). Se download falhar e a versão do PATH divergir da pinada → tool-error, não build com versão errada. |
| **rust** | `rust-toolchain.toml`/`rust-toolchain` pinando channel não instalado; build com toolchain diferente | `cargo`/rustup honra `rust-toolchain.toml`; script não força `+stable`/override. Channel pinado ausente offline → tool-error, não stable. |
| **swift** | `Package.swift` declara `swift-tools-version` acima do `swift` do PATH → build degradado | tool-error claro na incompatibilidade de tools-version. |
| **web** | N/A — sem manager/build-system (estático). Sem mudança. | — |

Formato da mensagem (no `$log` apropriado — `abs-deps.log`/`pr-deps.log`/`abs-build.log` conforme etapa):

```
::error::<causa especifica> -- <acao do usuario> (substituicao silenciosa produziria resultado incorreto)
```

O caller já emite `::error::falha ao resolver/medir <lang> -- ver <log>`; a causa detalhada vai no `$log`.

**Lockfile é autoritativo (LEI):** se um lockfile está presente mas o gerenciador correspondente não está no PATH (ex: `yarn.lock` + `yarn` ausente), isso é **tool-error → exit 2** com mensagem clara no log apontando o gerenciador faltante — **NUNCA** fazer fallback para outro gerenciador. Trocar de gerenciador silenciosamente produz resolução incorreta (peer-deps diferentes entre npm/yarn/pnpm) e mascara a causa real com um erro enganoso (ex: `ERESOLVE` do npm num projeto yarn).

Se a resolução de dependências **falhar** (rede, lockfile corrompido, registry privado sem auth, gerenciador do lockfile ausente): isso é **tool-error → exit 2** (`::error::falha ao resolver dependências de <lang> — <detalhe>`), **NÃO** `build` regredido.

## Sanitização numérica (`_num`, obrigatório)

Todo valor que alimenta `jq --argjson` (ou comparação aritmética / `awk`) DEVE ser sanitizado para número antes do uso. Função obrigatória em cada `lib/measure.sh` e `lib/output.sh`:

```bash
# Garante numero; qualquer coisa nao-numerica (vazio, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}
```

- Contadores sem resultado → `0`.
- `coverage` sem testes / tool sem output → `0` (nunca `"Unknown"`, nunca vazio). Em modo absoluto, `coverage=0` com threshold definido vira `violated`; sem threshold vira `reported`.
- Onde a ausência de número indica **tool quebrado** (não "ausência legítima"), preferir tool-error (exit 2) a mascarar com `0`. Ex: `cargo llvm-cov` segfault = exit 2; `0 testes logo sem cobertura` = `coverage 0` + segue.
- Aplicar `_num` em TODOS os pontos `--argjson`/`awk`/comparação dos `lib/`.

## Forbidden

Não pode silenciar gate sem fix real:

- Subir threshold de complexidade local sem registrar em `.qg.yaml` (com `until`).
- Marcar testes como ignored para "passar".
- Allow blanket de lints sem causa raiz.
- `--no-verify` em hooks git.

Causa raiz, ou bypass governado, ou `.qg.yaml` com `until`.

## Header obrigatório no script

Linha 2 de cada `<lang>/qg.sh`:

```bash
# QG_CONTRACT_VERSION=1
```

Ferramentas de validação leem isso para confirmar compatibilidade.
