# Quality Gate -- web (HTML + CSS estatico puro)

Documentacao especifica do gate `web`. Para o contrato comum, ver
[`../contract.md`](../contract.md).

## Escopo

O gate `web` cobre **sites estaticos puros**: HTML + CSS/SCSS sem build
system de front-end. Mede **somente** `fmt` + `lint`.

A sentinela de presenca (`--detect`) eh: existe `*.html` / `*.htm` /
`*.css` / `*.scss` na raiz do projeto **E NAO existe `package.json`**.

### React / Vue / Angular / Svelte NAO usam este gate

Projeto com `package.json` (mesmo que seja React, Vue, etc.) **e um
projeto nodejs** — coberto por [`nodejs/qg.sh`](nodejs.md), que ja roda
prettier/eslint/tsc sobre HTML/CSS/JSX/TS dele. O gate `web` so dispara
quando NAO ha `package.json` (estatico puro). Regras especificas de
framework entram no **ruleset do QG** (`nodejs/rules/`), nunca no config
do projeto-alvo (tamper-resistance — ver `../contract.md`).

## Build system

Nao ha build system. O gate apenas verifica formatacao e lint dos
arquivos estaticos. Ferramentas via `npx --yes` (nao exige instalacao
global): `prettier`, `stylelint`, `htmlhint`.

A sentinela de baseline-ausente reusa `qg_lang_present` (HTML/CSS na
raiz E sem `package.json`). Ausente no baseline -> warning + exit 0.

## Pre-requisitos com instalacao

### macOS

```bash
brew install node jq
# prettier / stylelint / htmlhint sao baixados sob demanda via 'npx --yes'.
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install -y nodejs npm jq
# prettier / stylelint / htmlhint via 'npx --yes' (Node 18+).
```

## Metricas -- o que cada uma mede em web

| Metrica | Ferramenta | O que conta |
|---|---|---|
| `fmt` | `prettier --check` (HTML+CSS+SCSS) | arquivos cujo estilo diverge do `.prettierrc.json` canonico do QG |
| `lint` | `stylelint` (CSS/SCSS) + `htmlhint` (HTML) | soma de erros de lint dos dois (regras canonicas do QG) |

`fmt`/`lint` seguem a regra de regressao padrao do contrato: PR falha se
`pr > base`.

## Metricas omitidas (e por que)

| Metrica | Por que omitida |
|---|---|
| `build` | HTML/CSS estatico nao tem etapa de build/compilacao. |
| `test`  | Nao ha conceito de teste unitario para markup/estilo estatico. |
| `complexity` | Nao ha metrica canonica de complexidade ciclomatica para HTML/CSS. |
| `coverage` | Nao ha execucao de codigo -> nao ha cobertura de linhas. |

Conforme o contrato, metricas omitidas **nao aparecem** na tabela texto
nem no array `metrics` do JSON (nunca `0`/`null` — isso falsificaria o
resultado). Mesmo principio do Swift, que omite `complexity`. A linha
correspondente no `README.md` raiz e marcada com `*`.

## Tamper-resistance

O gate impoe o PROPRIO ruleset (ver `../contract.md`, secao
"Tamper-resistance"):

- `prettier --config <QG>/web/rules/.prettierrc.json --no-editorconfig`
  — ignora `.prettierrc`/`.editorconfig` do projeto-alvo.
- `stylelint --config <QG>/web/rules/.stylelintrc.json` — `--config`
  com arquivo explicito sobrepoe qualquer `.stylelintrc` do projeto.
- `htmlhint --config <QG>/web/rules/.htmlhintrc` — ignora `.htmlhintrc`
  do projeto.

Override do ruleset **so** via env externa `QG_RULESET_DIR` (setada por
quem RODA o gate / pipeline), NUNCA lida de `.qg.yaml` ou arquivo do
projeto-alvo.

## Troubleshooting

| Sintoma | Causa provavel | Solucao |
|---|---|---|
| `ferramenta faltando: npx` | Node nao instalado | Instale Node 18+ (`brew install node` / `apt install nodejs npm`). |
| `--detect` sai 1 num site estatico | Existe `package.json` na raiz | Projeto e nodejs — use o gate nodejs. Se for estatico de verdade, remova/realoque o `package.json`. |
| `fmt` sempre alto e nao reduz | prettier reformataria muitos arquivos | Rode `npx prettier --write` localmente e commite (o gate so verifica, nao corrige). |

## Limitacoes conhecidas (V1)

- So estatico puro (sem `package.json`). Sites com bundler (Vite, etc.)
  sao nodejs, nao web.
- Conteudo dos `rules/` sao defaults da comunidade; calibracao fina e V2.
- HTML severamente malformado pode fazer o prettier emitir `[error]`
  (sintaxe) — isso ainda conta como divergencia de `fmt` quando ha
  arquivos `[warn]` no mesmo run; htmlhint reporta o problema estrutural
  via `lint`.
