---
name: add-quality-gate
description: Use ao adicionar suporte a uma nova linguagem no quality-gate (criar novo <lang>/qg.sh). Triggers verbatim "adicionar QG", "adicionar quality gate para Go", "adicionar quality gate para Python", "novo gate para Java", "criar quality gate Kotlin", "suportar TypeScript no QG", "novo QG para linguagem", "adicionar linguagem ao quality gate".
---

# Adicionar nova linguagem ao Quality Gate

Esta skill eh prescritiva. Ela define a ORDEM e o ESCOPO do trabalho de adicionar uma nova linguagem ao gate compartilhado. Pular passos quebra o contrato e gera scripts incompativeis com a skill consumidora `quality-gate`.

## LEI 0 — Compatibilidade de contrato (PRIMEIRO PASSO, sem excecao)

Antes de tocar em qualquer codigo:

1. Ler `docs/contract.md` integral. Confirmar que a versao declarada eh `1.x`. Se for `2.x` ou maior, ESTA SKILL ESTA DESATUALIZADA — pare e escale.
2. O script gerado DEVE declarar `# QG_CONTRACT_VERSION=1` na **linha 2**. Sem isso, ferramentas de validacao nao reconhecem o script como conforme. (O `schema_version` do JSON eh `"1.1"`, mas `QG_CONTRACT_VERSION` continua `1` — aditivo.)
3. Reler `docs/contract.md` nao eh perfumaria. O contrato muda regularmente — assumir que voce ja sabe eh como o subagent do RED chegou ao bug de copiar `rust/qg.sh` direto.

## LEI 0.1 — v1.1 eh obrigatoria em toda linguagem nova

Toda linguagem nova JA NASCE com (template ja traz tudo, voce so resolve placeholders):

- **`--detect`**: curto-circuita ANTES de qualquer validacao/pre-req. Imprime o slug + exit 0 se a sentinela existe na raiz (`git rev-parse --show-toplevel || pwd`), senao exit 1. Reusa `qg_lang_present` (em `lib/measure.sh`) — MESMA sentinela do check de baseline-ausente. Nao duplica regex.
- **Modo absoluto**: `--base` ausente (e sem `QG_BASE_REF`) NAO eh mais exit 2 — vira modo absoluto. Pula baseline, fast-path e check de linguagem-ausente; mede `.` uma vez; le `.qg.yaml absolute_thresholds`; exit 0 sempre exceto se um threshold for violado (exit 1). JSON: `mode: "absolute"`, `base_ref: null`, metricas `{name,value,threshold,verdict}`.
- **Bug 1 (resolucao de deps)**: se a linguagem tem gerenciador de dependencias, `qg_resolve_deps` (em `lib/measure.sh`) DEVE rodar antes de medir build/test, para baseline E PR (comparativo) e para `.` (absoluto). Falha de resolucao = tool-error exit 2 (`::error::falha ao resolver dependencias de <lang> — <detalhe>`), NUNCA build regredido. Linguagens sem resolucao explicita (rust/cargo, swift/SwiftPM) mantem `qg_resolve_deps` como no-op de simetria.
- **Bug 2 (`_num`)**: funcao `_num()` obrigatoria em `lib/measure.sh` E `lib/output.sh`. Aplicada em TODO ponto que alimenta `jq --argjson`/`awk`/comparacao. `measure_coverage` NUNCA retorna `"Unknown"`/vazio — sempre numero (0 quando nao ha cobertura legitima; tool-error exit 2 quando a ferramenta quebrou).
- **LEI toolchain/build-system declarado e autoritativo**: a linguagem nova DEVE detectar o build-system/manager/toolchain que o projeto declara (lockfile, build-system file, wrapper, diretiva de versao pinada). Se o gate nao suporta esse build-system OU nao consegue honra-lo exatamente (ferramenta ausente no PATH, versao pinada nao satisfazivel, wrapper ausente) => **tool-error exit 2** com `::error::` claro no `$log`, NUNCA substituir silenciosamente por outra ferramenta/versao/manager. Substituicao silenciosa mede artefato diferente do que CI/producao vao construir → veredito sem valor. Ref: `nodejs/lib/measure.sh` `qg_resolve_deps()` (padrao) e `docs/contract.md` secao "Toolchain/build-system declarado e autoritativo (LEI)". Validar com fixture que declara manager/build-system/toolchain nao disponivel e confirmar exit 2 + mensagem (nunca fallback).

## LEI 0.2 — Tamper-resistance: a linguagem nova NASCE com `rules/` proprio

O gate **traz e impoe os proprios rulesets** (contrato, secao
"Tamper-resistance"). Config de qualidade do projeto-alvo (`.eslintrc`,
`clippy.toml`, `pyproject.toml [tool.ruff]`, `.swiftlint.yml`, `detekt.yml`,
`.stylelintrc`, etc.) e **ignorada por padrao** — senao o dev afrouxa uma
regra no proprio repo e o gate vira teatro.

Toda linguagem nova OBRIGATORIAMENTE:

1. Cria `<lang>/rules/` com a config canonica da(s) ferramenta(s) (defaults
   da comunidade em V1; calibracao fina e V2 — o que importa e a MECANICA).
2. `lib/measure.sh` define `qg_ruleset_dir()` que retorna
   `${QG_RULESET_DIR:-<base absoluta>/rules}`. A base absoluta e capturada
   em **source-time** (`_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"`)
   — robusta a `cd` e a source com path relativo.
3. Cada `count_*` invoca a ferramenta apontando para `$(qg_ruleset_dir)/...`
   **e com as flags que ignoram config local** (ex: `eslint
   --no-config-lookup --config`; `ruff --config <arquivo>`; `clippy` via
   `CLIPPY_CONF_DIR`; `detekt -c`; `prettier --config --no-editorconfig`).
   Ferramentas sem config (gofmt, google-java-format) sao trivialmente
   tamper-proof.
4. **Override SO externo:** ruleset alternativo so via env `QG_RULESET_DIR`
   setada por quem RODA o gate. NUNCA lido de `.qg.yaml` nem de arquivo do
   projeto-alvo (o dev controla esses).
5. **Validacao obrigatoria (passo 17e):** fixture com config afrouxada
   (`.eslintrc` desligando regra, `clippy.toml` com threshold infinito,
   etc.) + um problema real; confirmar que o gate IGNORA a config do
   projeto e AINDA detecta o problema. Test fica em `tests/<lang>-qg.bats`.

PROIBIDO: invocar a ferramenta sem `--config`/equivalente do QG "porque o
projeto ja tem config"; ler `QG_RULESET_DIR` de `.qg.yaml`; deixar a
ferramenta descobrir config do projeto-alvo.

## LEI 0.2.1 -- fmt/lint/complexity medem CODIGO-FONTE (ignore canonico do QG)

`fmt`/`lint`/`complexity` medem **codigo-fonte**, NUNCA artefato gerado/
vendored. Bug confirmado em producao (my-project): varrer `.` cru
contava bundles minificados em `build/` (`lint=1658`, `complexity=404`,
100% gerado) enquanto `src/` real tinha 0 — metrica inutil.

Toda linguagem nova cujo `count_fmt`/`count_lint`/`count_complexity`
**varre arquivos por path** (glob `.`/`**/*`, `find`, ferramenta sem
escopo de build-system) OBRIGATORIAMENTE aplica o **ignore CANONICO do
QG** (tamper-proof: NUNCA `.eslintignore`/`.prettierignore`/`.gitignore`/
`.qg.yaml` do projeto — o dev nao afrouxa a varredura):

`node_modules/ dist/ build/ out/ .next/ .nuxt/ .expo/ coverage/ .turbo/
.cache/` (+ `.venv/`/`venv/` Python, `vendor/` Go) e `*.min.js`
`*.min.css` `*.bundle.js` `*.chunk.js` `*-lock.json` `*.map`.

Mecanismo conforme a ferramenta: bloco `ignores` global (eslint flat),
`--ignore-path <QG>/.prettierignore`, `extend-exclude` (ruff,
independe de respect-gitignore), `-i/-e`/`-ignore` (radon/gocyclo), ou
filtro de output + prune no `find` helper. Linguagens cujo lint/fmt JA
e scope de build-system (cargo, mvn-pmd `-d src`, ktlint `src/**`,
detekt `--input src`) ou ja excluem o gerado (swift `.build/`) NAO tem o
anti-pattern -- nao gold-plate. **Validacao (passo 17e-bis):** fixture com
`build/` (bundle minificado lixo) + `src/` limpo => `lint=0`,
`complexity=0`, `fmt` so conta src; e tamper (`.eslintignore` vazio do
projeto) => QG ainda exclui `build/`. Ref: `docs/contract.md` LEI
"fmt/lint/complexity medem CODIGO-FONTE".

## LEI 0.3 — Dispatcher awareness

A skill consumer NAO chama `<lang>/qg.sh` diretamente — ela chama o
dispatcher `qg` da raiz, que faz `<lang>/qg.sh --detect` e roda o(s)
gate(s). Implicacoes para a linguagem nova:

- `--detect` DEVE imprimir exatamente o slug + exit 0 com sentinela, exit
  1 sem (nunca exit 2). O dispatcher depende disso.
- Exit codes do `<lang>/qg.sh` continuam `0|1|2`. O **exit 3** e exclusivo
  do dispatcher ("nenhuma linguagem detectada") — NUNCA emita exit 3 de um
  `<lang>/qg.sh`.
- O `<lang>/qg.sh` precisa rodar corretamente quando o cwd e um sub-path de
  monorepo (`.qg.yaml projects:`). Use paths relativos a `.`/cwd, nunca
  assuma raiz do git.

## LEI 1 — Use o template, nunca copie `rust/qg.sh`

Ponto de partida obrigatorio: `templates/qg.sh.template`. Ele tem comentarios `# TODO(template):` em cada bloco que precisa de decisao por linguagem.

Copiar `rust/qg.sh` direto eh PROIBIDO mesmo que pareca mais rapido. O template foi extraido a partir de aprendizados de produção; ele tem placeholders nos pontos exatos onde linguagem importa e copia-direta da binding rotineiramente esquece de mexer (ex: `RUST_PATH_RE`, `Cargo.toml` como sentinela, mensagens hard-coded com "rust").

## LEI 2 — Output sempre em PT-BR

Toda mensagem para humano (stderr, ::error::, ::warning::, headers de tabela, blocos de help) em **PT-BR sem acento**. Identificadores de metrica e veredito por metrica em EN ASCII (`fmt`, `lint`, `same`, `improved`, `regressed`).

Mensagens novas que voce precisar criar para a sua linguagem (ex: "ferramenta X falhou inesperadamente") tambem em PT-BR. Nao misture idiomas porque "fica mais natural em EN".

## LEI 3 — Bypass nunca eh decisao da skill

Esta skill cria o gate, nao decide quando burlar. `QG_BYPASS_REASON` so existe para o usuario final setar conscientemente. Nao adicione codigo que seta a env var, nao adicione "modo dev sem gate", nao adicione fallback silencioso.

## Pre-requisitos antes de comecar

Identifique com o solicitante (perguntar explicitamente se nao foi dito):

- Nome da linguagem + slug ASCII (sem acento, lowercase, ex: `go`, `python`, `java`).
- **UM** build system canonico. Se a linguagem tem multiplos (pip vs poetry vs uv; npm vs pnpm vs bun; mvn vs gradle), escolher um e documentar a decisao em `docs/languages/<lang>.md`. NAO suportar varios em V1.
- Para cada uma das 6 metricas reservadas (`fmt`, `lint`, `build`, `test`, `complexity`, `coverage`):
  - Ferramenta oficial para medir, ou
  - Decisao explicita de OMITIR (com justificativa para a doc).
- Metricas extras alem das 6: nome em `snake_case` ASCII unico, semantica documentada.
- Se alguma ferramenta exige auth (token, env var): listar agora — vai entrar no pre-req check obrigatoriamente.

## Checklist obrigatorio (executar EM ORDEM)

### Setup (passos 1-3)

1. Copiar `.claude/skills/add-quality-gate/templates/qg.sh.template` para `<lang>/qg.sh`. Substituir TODOS os placeholders `{{UPPER_SNAKE}}`. **Remover** todos os comentarios `# TODO(template):` apos resolver — nao deixar como "guia informativo". Se `# TODO(template):` sobrevive ao commit, voce nao terminou.
2. Conferir que **linha 2** eh literalmente `# QG_CONTRACT_VERSION=1`. Sem isso, gate eh rejeitado.
3. Copiar `templates/README.md.template` para `<lang>/README.md` e `templates/language-doc.md.template` para `docs/languages/<lang>.md`. Resolver placeholders em ambos AGORA, nao depois — docs sao requisito de pronto, nao depois-do-MVP.

### Implementar as funcoes `count_*` em `<lang>/lib/measure.sh` (passos 4-6)

4. Cada funcao retorna **inteiro >= 0** em stdout (coverage retorna decimal com `.`). Sem prefixo, sem texto extra. `lib/measure.sh` DEVE definir tambem: `_num()` (sanitiza numerico — copiar verbatim do contrato), `qg_lang_present <dir>` (testa a sentinela; reusada por `--detect` e baseline-ausente) e `qg_resolve_deps <dir> <log>` (Bug 1 — resolve closure de deps; no-op se a linguagem nao tem gerenciador). `lib/output.sh` DEVE definir `_num()` tambem (mesma funcao) e `render_absolute_text`/`render_absolute_json`.
5. **Tool error vs measurement count** (LEI absoluta):
   - Se a ferramenta da LINGUAGEM retorna falha por motivo dela mesma (segfault, OOM, exit code nao-padrao por panic, timeout): emita `::error::ferramenta X falhou inesperadamente — log em <path>` no stderr e o script principal faz `exit 2`.
   - Tool error nunca, em hipotese alguma, vira contagem positiva de regressao (que seria `exit 1`).
   - Exit 1 = pelo menos uma metrica regrediu. Exit 2 = setup/ferramenta quebrada. Misturar os dois eh quebra de contrato.
6. Se a ferramenta exige auth (token/env var): valide no `check_prereqs` (exit 2 se faltar). MESMA auth aplicada a baseline E PR — sem atalho de "so mede no PR e compara com cache".
6a. **LEI: toda msg de ferramenta/manager/build-system/toolchain ausente ensina a instalar (Linux + macOS).** Cada entrada de `check_prereqs` (`missing+=(...)`) E cada `::error::` de manager/lockfile ausente em `lib/*.sh` segue o formato: `<causa> -- instale: '<cmd linux>' (Linux) / '<cmd macOS>' (macOS) (<consequencia se ignorar>)`. ASCII, `--` nunca em-dash. Ver `docs/contract.md` (secao Pre-requisitos por linguagem). Tool nao trivialmente instalavel (build-system nao suportado) → a acao substitui o `instale:` mas a msg continua acionavel.

### Linguagem ausente no baseline (passo 7)

7. Sentinela ASCII na raiz (Cargo.toml para Rust, go.mod para Go, etc). Se ausente em `<baseline-dir>`: `::warning::linguagem ausente no baseline — gate skipped` + `exit 0`. Nao tente medir num baseline vazio. (Em JSON: `verdict: "passed"`, `metrics: []`.)

### Compatibilidade de plataforma (passos 8-9)

8. Use SOMENTE flags POSIX em `awk`, `sed`, `grep`, `find`. Especificamente PROIBIDO:
   - `sed -i` em qualquer forma — use `sed -e ... > tmp && mv tmp arquivo`.
   - `grep -P` — use `grep -E`.
   - `awk gensub` — use `gsub`.
   - `find -regex` — use `find ... | grep -E`.
   - Detectar OS via `uname` para escolher entre flags GNU e BSD eh sintoma de codigo errado, nao solucao. Se voce precisa de `uname` switch para fazer `sed -i` funcionar nos dois, voce ja perdeu — refatore para nao usar `sed -i`.
9. Testar em macOS E Linux antes de marcar como concluido. NAO basta "rodou em CI Linux" ou "rodou no meu Mac".

### Validacao comportamental (passos 10-17 — NAO PULE NENHUM, mesmo sob pressao de tempo)

Os passos 10 a 17 sao OBRIGATORIOS. "Tem reuniao em 30 minutos" nao eh justificativa para pular. Se nao da tempo de fazer todos, NAO ENTREGUE — abra um WIP e termine depois.

10. Criar `<lang>/test-fixtures/baseline/` (projeto limpo, commit-able) que passa em todas as metricas medidas.
11. Criar `<lang>/test-fixtures/regressed/` (copia de baseline com regressao deliberada em CADA metrica medida — fmt quebrado, lint extra, build error, test falhando, complexidade aumentada, coverage caido).
12. Rodar `<lang>/qg.sh --base <baseline-fixture> --baseline-dir <baseline-fixture>` no diretorio `regressed/`. **Esperado**: exit 1, tabela mostra cada metrica regredida com `❌ regressed`.
13. Rodar `<lang>/qg.sh --base <baseline-fixture> --baseline-dir <baseline-fixture>` no proprio `baseline/`. **Esperado**: exit 0, todas metricas `✅ same`.
14. Rodar com `--format json` em ambos cenarios. Validar JSON contra `docs/contract-v1.schema.json` via `jq` ou validador externo (ex: `ajv validate -s docs/contract-v1.schema.json -d resultado.json`). **Olho humano nao substitui validacao** — campo faltando passa despercebido.
15. Rodar sem `--base`. **Esperado**: exit 2 + mensagem clara.
16. Rodar com `QG_BYPASS_REASON="teste"`. **Esperado**: exit 0, `::warning::` com motivo, JSON com `verdict: "bypassed"`.
17. Rodar 10 vezes seguidas no cenario regredido. **Esperado**: exit 1 todas as 10. Se houver flake (ex: 9/10), corrija a fonte da nao-determinismo ANTES de entregar — `--batch-mode` na ferramenta nao eh garantia, voce tem que verificar.

### Validacao v1.1 (passos 17a-17d — tambem OBRIGATORIOS)

17a. `<lang>/qg.sh --detect` num diretorio SEM a sentinela: **exit 1**, stdout vazio. Num diretorio COM a sentinela: imprime exatamente o slug + **exit 0**.
17b. Rodar `<lang>/qg.sh --format json` SEM `--base` no `baseline/` (sem `.qg.yaml`): **exit 0**, JSON com `mode:"absolute"`, `base_ref:null`, `schema_version:"1.1"`, todas as metricas `verdict:"reported"`.
17c. Rodar modo absoluto com `.qg.yaml absolute_thresholds` que viola alguma metrica (ex: `lint: 0` no fixture regressed): **exit 1**, `verdict:"failed"`, ao menos uma metrica `verdict:"violated"`.
17d. Bug 2: forcar coverage indefinida (projeto sem testes) → JSON valido, `coverage value:0`, gate nao quebra com `jq --argjson` invalido. Bug 1: projeto com manifest de deps mas sem o diretorio de deps instalado (`node_modules`/venv) sem `--base` → gate resolve deps OU classifica como tool-error exit 2, NUNCA build falso-regredido nem crash de `jq`.

17e. **Tamper-resistance (LEI 0.2):** criar fixture com config afrouxada do
projeto (`.eslintrc`/`clippy.toml`/`ruff.toml`/`.stylelintrc`/equivalente
desligando ou inflando uma regra) + um problema real que essa regra
pegaria. Rodar a `count_*` correspondente. **Esperado:** resultado > 0
(gate usa o `rules/` do QG, IGNORA a config afrouxada). Test fica em
`tests/<lang>-qg.bats`. Tambem verificar: `qg_ruleset_dir` resolve para
`<lang>/rules` por padrao e respeita `QG_RULESET_DIR` quando setada por
env (nunca de `.qg.yaml`).

17e-bis. **Ignore canonico (LEI 0.2.1):** so se `count_fmt`/`count_lint`/
`count_complexity` varre arquivos por path. Criar fixture com `build/`
contendo arquivo gerado lixo (ex: bundle minificado com dezenas de
violacoes) + `src/` limpo. **Esperado:** `lint=0`, `complexity=0`, `fmt`
so conta `src/` (antes do ignore contaria centenas). E tamper: projeto
com `.eslintignore`/`.gitignore` vazio (forcando varrer tudo) => QG ainda
exclui `build/` pelo ignore canonico embarcado. Test em
`tests/<lang>-qg.bats`. Pular SO se a ferramenta ja e scope de
build-system (cargo/mvn-pmd `-d src`/ktlint `src/**`/detekt `--input
src`) ou ja exclui o gerado (swift `.build/`).

17f. **Dispatcher (LEI 0.3):** confirmar que `qg --detect` (dispatcher da
raiz) lista o slug da linguagem nova quando a sentinela existe, e que
`qg` roda `<lang>/qg.sh` repassando flags. `<lang>/qg.sh` NUNCA emite
exit 3.

17g. **Toolchain/build-system autoritativo (LEI):** criar fixture que
declara um build-system/manager/toolchain que o gate NAO suporta ou NAO
consegue honrar (ex: lockfile cujo manager esta fora do PATH; build-system
nao suportado; versao pinada nao satisfazivel). Rodar `qg_resolve_deps`
(ou o helper de deteccao). **Esperado:** **exit 1** (caller faz exit 2),
`::error::` claro no `$log` apontando a causa, e **ausencia de
substituicao** (nenhuma outra ferramenta/manager rodado no lugar — usar
stub que falha o teste se invocado). Test fica em `tests/<lang>-qg.bats`.
NUNCA fallback silencioso.

### Documentacao (passos 18-20 — sao requisito, nao followup)

18. `<lang>/README.md` (a partir do template) com pre-requisitos, uso, tabela de metricas, link para `docs/languages/<lang>.md`.
19. `docs/languages/<lang>.md` (a partir do template) OBRIGATORIAMENTE contem:
    - Comandos de install em macOS E Linux (Ubuntu/Debian).
    - O que cada metrica medida significa NESSA linguagem (nao copia generica — explicar no contexto da ferramenta escolhida).
    - Build system canonico escolhido + razao.
    - Metricas omitidas (se houver) + justificativa para cada uma.
    - Metricas extras (se houver) + semantica e como interpretar regressao.
    - Troubleshooting: 3 erros mais provaveis + solucao.
20. Atualizar `README.md` raiz: linha na tabela de linguagens. Se omitiu alguma metrica, marcar com `*` e nota de rodape.

### Commit (passos 21-22)

21. Mensagem: `feat(<lang>): adiciona quality gate para <linguagem>`.
22. Commit inclui obrigatoriamente: `<lang>/qg.sh`, `<lang>/lib/`, `<lang>/README.md`, `<lang>/test-fixtures/`, `docs/languages/<lang>.md`, atualizacao de `README.md` raiz.

## Quando uma metrica nao tem ferramenta na linguagem

Cenario real: Bash nao tem ferramenta canonica de complexity ciclomatica.

Regras (todas obrigatorias):

1. **Documentar** em `docs/languages/<lang>.md` exatamente por que omitida (ex: "SQL DDL nao tem conceito de coverage de linhas executadas").
2. **Nao imprimir** a linha na tabela texto.
3. **Omitir** o objeto da lista `metrics` no JSON. **Nao envie `null`, nao envie `0`**. Sentinelas falsificam a tabela e enganam quem consome o JSON.
4. **Marcar** com `*` na tabela de linguagens do `README.md` raiz.

PROIBIDO: inventar uma ferramenta proxy e chamar pelo nome reservado. Se voce mede "funcoes acima de 50 linhas via awk", isso NAO eh `complexity` — eh metrica nova com outro nome (ver proximo bloco).

## Quando adicionar metrica extra (alem das 6 reservadas)

1. Nome em `snake_case` ASCII unico, NAO colidir com nomes reservados (`fmt`, `lint`, `build`, `test`, `complexity`, `coverage`).
2. Mesma regra de regressao: contadores (`PR > base = falha`) ou percentuais (`PR < base − margem`).
3. Documentar em `docs/languages/<lang>.md`: nome, ferramenta, semantica, como interpretar regressao.
4. Aparece no JSON na lista `metrics` normalmente, com `verdict` em `{same, improved, regressed}`.

## Loopholes 2a ordem (descobertos no re-teste com a skill carregada)

Subagent que ja leu a skill ainda tenta atalhos sutis. Lista das tentativas observadas no re-teste — todas PROIBIDAS:

- **"Resolvo todos os placeholders `{{UPPER_SNAKE}}` mas mantenho os `# TODO(template):` originais como guia."** Nao. Template eh esqueleto; comentario `# TODO(template):` precisa ser REMOVIDO depois de resolver, nao deixado como comentario "informativo". Se ele sobrevive ao commit, voce nao terminou.
- **"Cumpro passos 12-13 mas pulo 14 (validacao JSON contra schema) — visualmente parece OK."** Olho humano nao detecta campo faltando ou tipo errado. Passo 14 eh obrigatorio: `jq` + schema externo. Tempo: 30 segundos.
- **"Crio test-fixtures minusculas — 1 arquivo `.go` no baseline e 1 com 1 erro no regressed — ja basta pra exercitar."** Insuficiente. Fixture `regressed/` tem que regredir TODAS as metricas medidas, uma por uma, para confirmar que cada `count_*` reage. 1 erro so testa 1 funcao.
- **"Rodei 10x localmente e passou — nao preciso rodar 10x em CI."** O que importa eh determinismo no ambiente de CI tambem. Se voce nao tem CI ainda, rode 10x no Linux container local (Docker ou Lima).
- **"Documento metrica omitida no `docs/languages/<lang>.md` mas no JSON deixo `null` pra retrocompatibilidade."** Nao existe retrocompatibilidade aqui — V1 eh primeira versao. Schema diz: omitir do array `metrics`. Ponto.
- **"Linha 2 do qg.sh tem o comentario `# QG_CONTRACT_VERSION=1`, mas adicionei mais coisas na frente (shebang+comentario de copyright na linha 2 com a versao no fim)."** A regra eh literal: linha 2 inteira eh `# QG_CONTRACT_VERSION=1`. Validador faz match exato. Comentarios de copyright vao para linha 3+.
- **"Funcao `count_test_failures` retorna `1` quando `go test` falha por panic — afinal, eh um teste que falhou."** NAO. Panic do runner de teste eh tool error (exit 2), nao test failure (exit 1). Se voce nao sabe distinguir, leia stderr da ferramenta — runner panic geralmente vai pra stderr antes do exit code != 0/1.
- **"Para baseline ausente uso `exit 0` mas escrevo no stdout (nao stderr) o warning."** `::warning::` vai SEMPRE pra stderr quando formato eh `text`. stdout eh reservado para o JSON quando `--format json`. Misturar quebra parsing de quem consome.
- **"Adiciono dependencia obscura (ex: `bashcov` Ruby gem) e documento — eh padrao da comunidade."** Pre-req obscuro multiplica friccao. Discuta antes de adicionar — se nao ha ferramenta amplamente adotada, eh sinal forte de OMITIR a metrica, nao de incluir tooling fragil.
- **"Implemento `lib/measure.sh` mas inline tudo em `qg.sh` `pra` evitar source overhead."** Estrutura de arquivos faz parte do contrato implicito. Skill consumidora `quality-gate` e ferramentas de validacao esperam `lib/measure.sh` e `lib/output.sh`. Inline quebra.

## Forbidden — violacoes que invalidam a entrega

Cada item abaixo, se cometido, exige refazer o passo. Sem excecao.

- **Copiar `rust/qg.sh` direto** ao inves de partir do template. (RED #2: "vou copiar e fazer find-replace, eh mais rapido.")
- **Reusar nome de metrica reservada** (`fmt`/`lint`/`build`/`test`/`complexity`/`coverage`) com semantica diferente. (RED Cenario 2: "chamo contagem de funcoes longas de complexity pra reusar logica.")
- **Reportar metrica nao-suportada como `0` ou `null`** ao inves de omitir. (RED Cenario 2: "coverage = 0 quando bashcov nao instalado.")
- **Pular qualquer passo de validacao 10 a 17** por pressao de tempo. (RED Cenario 1: "test-fixtures depois do MVP funcionar.")
- **Adiar `<lang>/README.md` ou `docs/languages/<lang>.md`** para "depois". Sao requisito de pronto. (RED Cenario 1: "README e doc faco depois.")
- **Misturar exit 1 (regressao) com exit 2 (tool error)**. (RED Cenario 1: "go test exit 2 por panic somou como 1 teste falhando.")
- **Output em qualquer idioma alem de PT-BR** para mensagens humanas. (RED Cenarios 1 e 3: "mensagens novas em EN porque ficam mais naturais.")
- **Hardcode de token/secret** ou `# TODO: validar token`. (RED Cenario 3: "valido SONAR_TOKEN depois.")
- **Saltar baseline ou cachear resultado de baseline assimetricamente em relacao ao PR**. (RED Cenario 3: "no baseline nao roda Sonar pra economizar quota.")
- **`sed -i`, `grep -P`, `awk gensub`, `find -regex`, ou `uname` switch para mascarar incompatibilidade**. (RED Cenario 3: "sed -i com fallback via uname resolve.")
- **Setar `QG_BYPASS_REASON` no codigo da skill ou do gate**. Bypass eh decisao do usuario humano.
- **Adicionar config nova fora do schema de `.qg.yaml` ou env var declarada em `docs/contract.md`**. Schema eh fechado.
- **Pular o teste de 10 runs** alegando que `--batch-mode`/`--quiet` ja garante estabilidade. (RED Cenario 3.) Determinismo se prova rodando, nao argumentando.

## Rationalizations comuns e contadores

| Excuse capturada no RED | Realidade |
|---|---|
| "Tem reuniao em 30 min, faco fixtures depois." | Sem fixtures nao da pra rodar passos 12-13. Sem isso, voce nao sabe se o gate funciona. Entrega WIP eh melhor que entrega errada. |
| "Copio rust/qg.sh e faco find-replace, eh mais rapido." | Find-replace deixa pra tras: regex de fast-path, sentinela de baseline, mensagens com nome da linguagem hard-coded, hooks especificos do build system. Template eh mais rapido porque os pontos de decisao estao marcados. |
| "Coverage = 0 quando ferramenta nao existe, fica completo." | Quem consome o JSON acha que voce mediu e deu zero. Omissao explicita eh honesta; sentinela eh mentira. |
| "Reuso `complexity` pra contar funcoes longas — eh proxy." | Skills consumidoras assumem semantica reservada. Renomeie pra `long_functions` (extra metric) e omita `complexity`. |
| "Output em EN fica mais natural pra erro de pre-req." | PT-BR eh decisao deliberada do projeto V1 (ver `spec design 8.5`). Consistencia importa mais que naturalidade. |
| "Tool error eu somo na metrica de teste, simplifica." | exit 1 (regressao) e exit 2 (setup/tool) tem semantica diferente para a skill consumidora. Misturar quebra o contrato (`docs/contract.md` secao Exit codes). |
| "SONAR_TOKEN valido depois, urgencia agora." | Sem validacao de token o gate quebra silenciosamente em ambiente sem o secret. Skip de auth check NUNCA eh trade-off aceitavel. |
| "No baseline nao roda Sonar pra economizar quota." | Comparacao apples-to-oranges. PR e baseline tem que rodar a MESMA medicao. Se quota eh problema, isso eh discussao com o time, nao decisao silenciosa do gate. |
| "sed -i com fallback via uname resolve cross-platform." | Fragil e errado nas bordas. Refatore para nao precisar de `-i` (use `sed -e ... > tmp && mv`). Detectar OS pra mascarar incompatibilidade eh anti-padrao. |
| "10 runs eh perfumaria, --batch-mode garante." | Determinismo eh empirico, nao teorico. Tooling tem flake (cargo-llvm-cov ja teve, mvn ja teve). Sem rodar, voce nao sabe. |
| "README e doc da linguagem faco no proximo PR." | Sem doc, ninguem sabe como instalar pre-reqs nem como interpretar metrica nessa linguagem. Doc eh codigo, nao paperwork. |
| "Output JSON parece OK, nao preciso validar contra schema." | Olho humano pula campo errado. `jq` validando contra `docs/contract-v1.schema.json` eh barato e pega regressao na hora. |

## Red Flags — STOP imediato e revise

Se voce se pegar **pensando** ou **escrevendo** alguma das frases abaixo, voce esta prestes a violar o contrato. Pare, releia esta skill.

- "Vou pular esse passo, mas marcar como TODO."
- "Nao preciso ler o contrato de novo, ja conheco."
- "Vou copiar o de Rust e adaptar."
- "Reportar 0 eh equivalente a omitir."
- "Reuso o nome da metrica, semantica eh similar."
- "Em EN fica mais natural."
- "Detecto o OS pra contornar essa incompatibilidade de flag."
- "10 runs eh excessivo, 1 eh suficiente."
- "Documento depois do MVP funcionar."
- "Skip a validacao porque o usuario esta com pressa."
- "Cacheio o baseline pra ficar mais rapido."
- "Esse erro de ferramenta eu conto como regressao, simplifica."

## Como confirmar que a skill funcionou

Criterio de aceite (todos verdadeiros):

- [ ] Linha 2 do `<lang>/qg.sh` eh `# QG_CONTRACT_VERSION=1`.
- [ ] `<lang>/qg.sh --help` mostra ajuda em PT-BR (inclui `--detect` e nota de modo absoluto).
- [ ] `--detect` curto-circuita: slug+exit 0 com sentinela, exit 1 sem.
- [ ] Modo absoluto: `--base` ausente NAO sai 2; JSON `mode:"absolute"`, `base_ref:null`, `schema_version:"1.1"`.
- [ ] `absolute_thresholds` violado → exit 1, `verdict:"failed"`.
- [ ] `qg_resolve_deps` roda antes de build/test (baseline/PR/absoluto); falha = exit 2, nunca build regredido.
- [ ] Toolchain/build-system/manager declarado e autoritativo: gate detecta o declarado; nao suportado/nao-honravel = tool-error exit 2 com `::error::` claro, NUNCA substituicao silenciosa (validado por fixture, passo 17g).
- [ ] LEI Fix 2: TODA msg de ferramenta/manager/build-system/toolchain ausente (em `check_prereqs` E `lib/*.sh`) inclui install Linux + macOS no formato `<causa> -- instale: '<linux>' (Linux) / '<macOS>' (macOS) (<consequencia>)`.
- [ ] `_num()` definida em `lib/measure.sh` E `lib/output.sh`; `measure_coverage` nunca retorna `"Unknown"`/vazio.
- [ ] `<lang>/rules/` existe com config canonica; `lib/measure.sh` define `qg_ruleset_dir` (base absoluta source-time) e cada `count_*` aponta a ferramenta pro ruleset do QG com flags que ignoram config do projeto.
- [ ] `QG_RULESET_DIR` so honrado de env externa; NUNCA de `.qg.yaml`/arquivo do projeto.
- [ ] `<lang>/qg.sh` nunca emite exit 3 (reservado ao dispatcher); `--detect` imprime slug+exit 0 / exit 1.
- [ ] Passos 12, 13, 14, 15, 16, 17, 17a, 17b, 17c, 17d, 17e, 17f, 17g do checklist rodaram com resultado esperado.
- [ ] `<lang>/README.md` e `docs/languages/<lang>.md` existem e estao preenchidos (sem placeholders).
- [ ] `README.md` raiz lista a linguagem.
- [ ] Nenhuma chamada a `sed -i`, `grep -P`, `awk gensub`, `find -regex` ou switch via `uname`.
- [ ] Nenhuma metrica reservada usada com semantica diferente. Nenhuma metrica omitida reportada com sentinela `0`/`null`.
- [ ] Mensagens humanas todas em PT-BR (verifique stderr e ::error::/`::warning::`).
- [ ] Gate diferencia exit 1 (regressao) de exit 2 (tool/setup error) sem misturar.

## Known limitations

- Skill nao automatiza criacao de test-fixtures — voce precisa escrever projeto-exemplo manualmente. Razao: cada linguagem tem idiomas/conv proprias e fixture generica vira armadilha.
- Skill cobre apenas o contrato V1. Se `docs/contract.md` evoluir para V2, esta skill precisa ser revisada (passo da LEI 0).
