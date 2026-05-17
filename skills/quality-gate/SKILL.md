---
name: quality-gate
description: Use ao verificar qualidade do codigo antes de abrir um PR. Triggers verbatim em PT-BR — "rodar quality gate", "rodar QG", "verificar qualidade", "checar qualidade antes do PR", "validar antes do PR", "esta pronto para PR", "qa antes do push", "rodar gate", "rodar o gate" — e em EN — "run quality gate", "run QG", "check quality before PR". Invoca o dispatcher do gate empacotado neste plugin, interpreta o JSON e renderiza analise em PT-BR. NUNCA seta `QG_BYPASS_REASON` por iniciativa propria. NUNCA edita codigo para "fazer passar" o gate. NUNCA roda `gh pr create` ou `git push` automaticamente.
---

# Quality Gate

Skill que invoca o **dispatcher** do gate compartilhado
(`quality-gate`) localmente, interpreta o resultado e orienta o
usuario. O gate (dispatcher + scripts das linguagens) e empacotado
neste mesmo plugin.

A deteccao de linguagem NAO e mais responsabilidade desta skill nem da
IA. O dispatcher `${CLAUDE_PLUGIN_ROOT}/qg` detecta a(s)
linguagem(s) sozinho (100% shell, zero IA) e roda o(s) gate(s)
correspondente(s). Esta skill so chama o dispatcher e interpreta o JSON.

## LEI — bypass NUNCA e decisao da skill

Se o gate retorna `regressed`/`failed`, a skill **REPORTA**. Ela:

- NAO passa `QG_BYPASS_REASON` automaticamente.
- NAO edita codigo (testes, asserts, configs) para "fazer passar" o gate.
- NAO marca testes com `#[ignore]` / `skip` / `xit` para o gate verdejar.
- NAO adiciona arquivos em `extra_fast_path_paths` para o gate ignorar
  o trecho em regressao.
- NAO edita config de qualidade do projeto (`.eslintrc`, `clippy.toml`,
  `.stylelintrc`, etc.) para afrouxar regra. **Inutil de qualquer forma:**
  o gate impoe o proprio ruleset (tamper-resistance) e ignora a config do
  projeto-alvo por padrao.
- NAO roda `gh pr create`, `git push`, `git push --no-verify` ou
  `--force` apos veredito verde. Verde e **sinal de luz**, nao **acao**.

Bypass governado existe (`QG_BYPASS_REASON=...`), mas e **decisao do
humano**. Quando a skill detecta que o usuario esta sob pressao e
sugerindo bypass, ela **confirma o motivo por escrito antes** e **avisa
que isso fica em audit log**. Nunca seta a variavel sozinha.

## Quando usar

Triggers explicitos do usuario:
- "rodar quality gate", "rodar QG", "rodar gate", "rodar o gate"
- "verificar qualidade", "checar qualidade antes do PR"
- "validar antes do PR", "esta pronto para PR"
- "qa antes do push"
- equivalentes EN: "run quality gate", "run QG", "check quality before PR"

Tambem fire automatico quando o usuario diz "vou abrir PR" / "abrir PR
agora" / "vamos fazer push". Nesses casos, ofereca rodar o gate
**antes** do PR, mas pergunte se o usuario ja rodou.

Nao usar:
- Se o usuario **explicitamente** disse "skip o gate" / "nao rode o QG"
  / "ja rodei o gate" nesta sessao. Confie e siga. **NAO inferir** a
  partir de pistas vagas (ex: "ta tudo verde aqui" nao e dispensa).

## Pre-requisitos

- `git` instalado (o dispatcher usa para resolver a base ref).
- Pre-requisitos de cada linguagem suportada (documentados em
  `${CLAUDE_PLUGIN_ROOT}/<lang>/README.md`).

## Fluxo (passos obrigatorios — nao pular)

### 1. Localizar o dispatcher (empacotado neste plugin)

O gate (dispatcher `qg` + os scripts `<lang>/qg.sh` + contrato) e
**empacotado dentro deste plugin**. NAO ha clone nem `git pull` em
runtime — o dispatcher vive em `${CLAUDE_PLUGIN_ROOT}/qg` e e atualizado
junto com o plugin (`claude plugin update` / auto-update). Isso elimina
qualquer janela de staleness e divergencia de cache.

```bash
GATE_PATH="${QG_PATH:-$CLAUDE_PLUGIN_ROOT}"
test -x "$GATE_PATH/qg" || { echo "::error::dispatcher 'qg' nao encontrado em $GATE_PATH -- instalacao do plugin corrompida (reinstale: /plugin install)"; exit 2; }
```

**Override de desenvolvedor:** se a env var `QG_PATH` esta setada, use
esse path direto (util para quem esta editando o proprio gate localmente
fora do plugin instalado).

### 2. Detectar `--base`

Tente em ordem (primeiro que existir vence):

1. `git symbolic-ref refs/remotes/origin/HEAD` (default branch real do remote).
2. `git rev-parse --verify --quiet origin/main`.
3. `git rev-parse --verify --quiet origin/master`.
4. `git rev-parse --verify --quiet origin/develop`.

Se **nenhum** existir: rode em **modo absoluto** (sem `--base`) — ver
secao 4. NAO chute `HEAD~1`/`HEAD^`/SHA generico. Em duvida entre
absoluto e perguntar, prefira **perguntar** ao usuario qual ref usar.

**Override:** se o usuario disse "rodar QG contra `release/2026-Q2`" ou
similar, use `--base origin/release/2026-Q2`. Sempre prefixar com
`origin/` se nao tiver, exceto se o usuario passou um SHA absoluto.

### 3. Invocar o dispatcher com `--format json`

Sempre o **dispatcher** `qg` (nunca `<lang>/qg.sh` direto — a deteccao
de linguagem e do dispatcher, 100% shell). Sempre `--format json`. Use
um `--log-dir` timestamped para nao colidir entre execucoes:

```bash
LOG_DIR="/tmp/qg-$(date -u +%Y%m%dT%H%M%S)"
mkdir -p "$LOG_DIR"

GATE_PATH="${QG_PATH:-$CLAUDE_PLUGIN_ROOT}"

"$GATE_PATH/qg" \
  --base "<ref>" \
  --format json \
  --log-dir "$LOG_DIR" \
  > "$LOG_DIR/result.json" 2> "$LOG_DIR/stderr.log"
GATE_EXIT=$?
```

Em **modo absoluto** (sem base ref disponivel), omita `--base`:

```bash
"$GATE_PATH/qg" --format json --log-dir "$LOG_DIR" \
  > "$LOG_DIR/result.json" 2> "$LOG_DIR/stderr.log"
GATE_EXIT=$?
```

#### Mapa de exit codes do dispatcher

| Exit | Significado | O que a skill faz |
|------|-------------|-------------------|
| `0`  | `passed` / `bypassed` / fast-path / modo absoluto sem violacao | Renderiza verde. NAO abre PR. |
| `1`  | `regressed` (comparativo) ou `failed` (threshold absoluto violado) | Renderiza tabela + analise dos logs. NAO abre PR. NAO sugere bypass. |
| `2`  | Erro de ferramenta / pre-requisito faltando / `.qg.yaml` invalido | Repassa a msg de `stderr.log` literalmente. NAO interpreta JSON. NAO instala pre-req. PARA. |
| `3`  | **Nenhuma linguagem suportada detectada** (exclusivo do dispatcher) | Reporta: "nenhuma linguagem suportada — abra issue em `quality-gate` ou rode a skill `add-quality-gate` no repo do gate". NAO improvisa gate ad-hoc. |

Se `GATE_EXIT == 2`: **NAO interprete o JSON como veredito**. Reporte o
erro de ferramenta literalmente (`$LOG_DIR/stderr.log`) e PARE. **NAO
instale o pre-requisito por iniciativa propria** (toolchain global do
usuario); sugira o comando e espere confirmacao. **NAO re-rode** ate o
pre-requisito ser instalado pelo usuario.

Se `GATE_EXIT == 3`: linguagem fora do escopo. NAO rode `npm test +
eslint` e chame de "gate". NAO escreva `<lang>/qg.sh` no projeto. PARE e
oriente abrir issue / usar `add-quality-gate`.

### 4. Interpretar o JSON (single ou monorepo)

O dispatcher emite **um de dois formatos**:

- **1 linguagem** → o JSON do `<lang>/qg.sh` direto (single object):
  `{ schema_version, mode, language, branch, base_ref, verdict,
  metrics:[...] }`.
- **N linguagens / monorepo** → envelope:
  `{ schema_version, aggregate_verdict, results:[ <single>, ... ] }`.

```bash
if jq -e 'has("results")' "$LOG_DIR/result.json" >/dev/null 2>&1; then
  # monorepo: itere .results[]; veredito global = .aggregate_verdict
else
  # single: use o objeto direto; veredito = .verdict
fi
```

**Campo `mode`:**
- `"comparative"` (ou ausente, legacy 1.0): metricas
  `{name, base, pr, delta, verdict}`; `verdict` global ∈
  `passed|regressed|bypassed`.
- `"absolute"` (modo absoluto, sem `--base`): metricas
  `{name, value, threshold, verdict}`; `base_ref: null`; `verdict`
  global ∈ `passed|failed|bypassed`. Exit 0 salvo se `.qg.yaml`
  definir `absolute_thresholds` e algum for violado (exit 1).

### 5. Renderizar resultado em PT-BR (com analise, nao so tabela)

Para cada metrica em regressao/violacao, ler o log correspondente em
`$LOG_DIR/pr-<metric>.log` (ou `abs-<metric>.log` no modo absoluto) e:

1. Citar o arquivo:linha exato do erro.
2. Sugerir uma correcao especifica (ex: "cobrir o branch de retry em
   `payment::charge()`", nao "aumentar coverage").
3. Apontar arquivos novos do PR sem teste correspondente (`git diff
   --name-only <base>...HEAD`) — so no modo comparativo.

Formato sugerido (modo comparativo):

```
Quality Gate — <branch> vs <base>

✅ fmt        0 → 0      same
✅ lint       3 → 2      improved
❌ test       0 → 1      REGREDIU
   → Falha em: tests/api_integration::test_user_creation
   → Log: <LOG_DIR>/pr-test.log:142
❌ coverage  82.3% → 79.8%  REGREDIU (margem 1.0pp, queda 2.5pp)
   → ~120 linhas novas em src/services/payment.rs sem teste.
   → Sugestao: cobrir o branch de retry de payment::charge().

Veredito: NAO ABRA O PR. Corrija test + coverage primeiro.
```

Modo absoluto (sem `--base`): renderize valor x limite, `verdict` por
metrica ∈ `ok|violated|reported`. Sem `absolute_thresholds` no
`.qg.yaml`, tudo vira `reported` e o gate sai 0 — reporte como
"snapshot informativo, sem base para comparar; exit 0".

Monorepo: renderize um bloco por `results[]` (cabecalho com
`.language`) e um veredito final = `.aggregate_verdict`.

A analise (sugestoes + apontamento de arquivo) **vem do Claude lendo os
logs `pr-*.log`/`abs-*.log`** quando ha regressao. Nao vem do gate.

### 6. Comportamento por veredito

- `passed` → tabela verde + uma linha "OK pra abrir PR". NAO roda
  `gh pr create`. NAO roda `git push`. Verde = sinal, nao acao.
- `regressed` / `failed` → tabela com analise + sugestoes. NAO abra PR.
  NAO sugira `QG_BYPASS_REASON`. Pergunte: "quer que eu te ajude a
  corrigir <metrica>?"
- `bypassed` → warning explicando que bypass esta ativo, o motivo
  declarado (`QG_BYPASS_REASON`), e lembre que isso fica em audit log.
  NAO comemore o "verde".

## Forbidden (regras anti-burla)

A skill NUNCA faz nenhuma das seguintes acoes — limites duros, sem
excecao por urgencia, hotfix, ou pedido vago:

1. **Setar `QG_BYPASS_REASON` por iniciativa propria.** Mesmo com
   "producao caiu". Confirme por escrito; oriente o usuario a exportar a
   variavel ele mesmo; avise sobre audit log.
2. **Editar codigo / testes / config para "fazer passar".** Sem teste
   fake, sem `#[ignore]`, sem remover assercao, sem comentar teste flakey.
3. **Editar `.qg.yaml`** para `extra_fast_path_paths`/margens com fim de
   passar. So se o usuario pediu explicitamente E justificou.
4. **Editar config de qualidade do projeto** (`.eslintrc`, `clippy.toml`,
   `.stylelintrc`, etc.) para afrouxar regra. Alem de proibido, e inutil:
   o gate impoe o proprio ruleset e ignora a config do projeto.
5. **Chamar `<lang>/qg.sh` direto** em vez do dispatcher `qg`. A deteccao
   e do dispatcher. So use `<lang>/qg.sh` se o usuario explicitamente
   pediu para depurar um gate especifico.
6. **Inventar gate ad-hoc para exit 3.** Nao roda `npm test + eslint`,
   nao escreve `<lang>/qg.sh` local. PARE e oriente abrir issue.
7. **Rodar `gh pr create` / `git push` / `--no-verify` / `--force`**
   apos qualquer veredito. Verde libera **opcao**, nao executa o PR.
8. **Auto-corrigir warnings/erros sem permissao.** Apos rodar o gate,
   se houver ajustes triviais, **proponha** com diff antes de commitar.
9. **Confundir saida de ferramentas locais com veredito do gate.** So
   afirme verde apos o JSON do dispatcher retornar `passed`.
10. **Reduzir/desabilitar suite para apertar prazo.**
11. **Reportar verde sem ter rodado o gate.**
12. **Desqualificar o resultado do gate.** Se ha suspeita real de bug no
    gate, abra issue em `quality-gate` E ainda assim reporte a
    regressao; quem decide ignorar e o humano via `QG_BYPASS_REASON`.
13. **Instalar pre-requisitos do gate por iniciativa propria.** Sugira o
    comando, espere confirmacao.
14. **Inferir consentimento de pular o gate.** Dispensa precisa de
    afirmacao explicita ("nao rode o QG", "skip o gate", "ja rodei").

## Rationalizations capturadas (RED phase) — contadores explicitos

### Cenario 1 — Dev impaciente

| Rationalization | Refutacao da skill |
|---|---|
| "Rodei `cargo test` e passou, ta pronto pra PR." | `cargo test` e 1 das metricas. Sem o dispatcher comparando tudo com baseline, nao e o gate. |
| "Vou ja rodar `gh pr create` enquanto isso." | Verde libera **opcao** de PR. NUNCA executar `gh pr create` automaticamente. |
| "O fmt deu diff, vou rodar `fmt` e commitar junto." | NAO autocorrigir misturado com verificacao. Reporte, proponha, peca confirmacao. |
| "Esse warning ja existia antes, nao e do PR." | O gate compara base vs PR. Se aponta como regressao, leve ao usuario. |
| "Coverage caiu 0,3pp, e ruido." | Margem e do contrato/`.qg.yaml`. Skill nao redefine. |

### Cenario 2 — Hotfix sob pressao

| Rationalization | Refutacao da skill |
|---|---|
| "Producao caiu, vou de `--no-verify`." | `--no-verify` pula hooks locais, nao bypassa o gate. Bypass = `QG_BYPASS_REASON` setado pelo humano. |
| "Vou setar `QG_BYPASS_REASON=hotfix`." | A skill NUNCA seta a variavel. Oriente o usuario a exportar no shell. |
| "Afrouxo o `.eslintrc` so nesse arquivo." | Inutil: o gate impoe o ruleset do QG e ignora config do projeto. Alem de proibido. |
| "Marco esse teste com `#[ignore]`." | Reduzir suite e burlar o gate. Proibido. |
| "Sobe agora, abro issue depois." | Sem rastro. Se vai pular, vai com `QG_BYPASS_REASON` (audit log). |

### Cenario 3 — Linguagem nao suportada (exit 3)

| Rationalization | Refutacao da skill |
|---|---|
| "Aqui e Node, mas `npm test + eslint` cobre bem." | Gate ad-hoc sem contrato. PARE, oriente issue / `add-quality-gate`. |
| "Vou rodar `<lang>/qg.sh` mesmo sem sentinela." | A deteccao e do dispatcher. Exit 3 = fora do escopo. PARE. |
| "A linguagem X ja deve ser suportada." | Atualize o plugin (claude plugin update) e re-rode o dispatcher. Se exit 3 persiste, PARE e oriente issue. |
| "Crio um `<lang>/qg.sh` aqui rapidao." | Adicionar linguagem e tarefa do repo do gate, com `add-quality-gate`. |
| "Falo que rodou OK porque os testes passaram." | Reportar verde sem JSON do dispatcher e mentira. PARE. |

## Padroes cross-cenario (resumo)

1. **Confunde ferramentas locais com o gate.** O gate e o dispatcher
   `${CLAUDE_PLUGIN_ROOT}/qg --format json`.
2. **Auto-corrige sob pressao.** So **propor** ao usuario.
3. **Toma decisao de bypass por iniciativa propria.** Nunca.
4. **Inventa abstracoes faltantes.** Exit 3 vira "abra issue", nao
   "improviso".
5. **Pula da medicao para a acao.** Verde nao chama `gh pr create`.

## Red Flags — STOP imediato

- "Vou setar QG_BYPASS_REASON pra ele, ja que e hotfix."
- "Vou rodar o formatador antes do gate pra nao acusar diff."
- "O coverage caiu pouquinho, da pra ignorar."
- "Vou comentar esse teste flakey."
- "Afrouxo o .eslintrc/.stylelintrc do projeto." (Inutil — gate impoe o
  proprio ruleset.)
- "Exit 3? Vou improvisar um gate aqui." (PARE — abra issue.)
- "Rodei os testes, ta verde."
- "Verde, ja vou abrir o PR pra adiantar."
- "Esse gate tem algum bug, ignora a regressao."
- "Vou instalar o pre-req pra ele rapidinho e re-rodo."
- "O usuario disse que ta tudo verde, posso pular."

## Limitacoes conhecidas (V1)

- Linguagens suportadas: fonte de verdade e a tabela "Linguagens
  suportadas" no `README.md` do repo do gate. Hoje: Rust, Go, Python,
  Node.js, Java, Swift, Kotlin, **Web (HTML/CSS estatico)**. O gate
  `web` so mede `fmt`+`lint` e so dispara em projeto SEM `package.json`;
  React/Vue/etc. com `package.json` = projeto nodejs.
- A deteccao e 100% do dispatcher (`qg --detect`); a skill NAO mantem
  tabela de sentinelas.
- Gate empacotado no plugin; atualiza junto com o plugin (`claude plugin update` / auto-update). Sem clone/cache em runtime. Override para dev local: env `QG_PATH`.
- A skill nao instala pre-requisitos do gate. Exit 2 → repassa a
  mensagem do gate ao usuario.

## Detalhes do contrato

Documentacao de referencia (no repo do gate, apos clone):

- `${CLAUDE_PLUGIN_ROOT}/docs/contract.md` — contrato CLI, dispatcher,
  tamper-resistance, `.qg.yaml projects:`.
- `${CLAUDE_PLUGIN_ROOT}/docs/output-format.md` — formato JSON/texto,
  incluindo o envelope de monorepo (`aggregate_verdict`/`results`).
- `${CLAUDE_PLUGIN_ROOT}/docs/consume.md` — como usar localmente.
- `${CLAUDE_PLUGIN_ROOT}/<lang>/README.md` — pre-requisitos da linguagem.
