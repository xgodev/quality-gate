# Quality Gate -- Node.js

Documentacao especifica do gate Node.js. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Node.js assume **npm** + `package.json`. As ferramentas de medicao (prettier, eslint, c8, typescript) sao baixadas sob demanda via `npx --yes` -- nao exigem `npm install` no projeto-alvo. Se o projeto ja tem `node_modules` com versoes especificas, `npx` prioriza-as.

V1 NAO suporta multi-build (yarn, pnpm, bun). A sentinela do baseline eh `package.json` -- compativel com qualquer um, mas as ferramentas-canonica do gate dependem de `npm`/`npx`. Em projetos pnpm/yarn-only o gate funciona se o repo tem `package.json` (todos tem).

**Resolucao de deps por lockfile:** o gate detecta o lockfile e usa o manager correto (lockfile autoritativo -- nunca fallback silencioso): `pnpm-lock.yaml`->`pnpm i --frozen-lockfile`; `yarn.lock`->Yarn (ver abaixo); `package-lock.json`->`npm ci`; senao `npm install`. **Yarn Berry vs classic:** se ha `.yarnrc.yml` na raiz o projeto usa Yarn Berry (v2+) e o gate roda `yarn install --immutable` (Berry nao aceita `--frozen-lockfile`); sem `.yarnrc.yml` e Yarn classic (v1) e o gate roda `yarn install --frozen-lockfile`. Manager ausente continua tool-error (exit 2) com mensagem de install Linux+macOS.

## Pre-requisitos com instalacao

### macOS

```bash
brew install node jq
# prettier/eslint/c8/typescript: nao instalar -- npx --yes baixa sob demanda.
```

### Linux (Ubuntu/Debian)

```bash
# Node.js LTS atual via NodeSource (apt nativo costuma estar defasado):
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs jq
```

## Metricas -- o que cada uma mede em Node.js

### `fmt` -- formatacao

Roda `npx --yes prettier --check .`. Conta linhas `[warn] <path>` (cada arquivo divergente).

**Configuracao:** se o projeto tem `.prettierrc*` ou `prettier.config.*`, eh respeitado. Idem `.prettierignore`. Sem config, defaults do prettier.

**Como interpretar regressao:** PR introduziu arquivo desformatado. Solucao: `npx prettier --write .`.

### `lint` -- eslint

Roda `npx --yes eslint .` se o projeto tem config eslint (`eslint.config.*`, `.eslintrc.*`); senao `npx --yes eslint --no-config-lookup --rule '{"no-unused-vars":"error"}' .`.

Conta linhas no formato `  N:N  error  msg  rule` (saida stylish do eslint).

**Configuracao:** se o projeto tem `eslint.config.js` (flat config eslint v9+) ou `.eslintrc.json` (legacy), eh respeitado. Sem config, fallback minimo (apenas `no-unused-vars`).

**Como interpretar regressao:** PR introduziu issue que eslint detecta. Solucao: `npx eslint --fix .` (auto-fix simples), ou ler `target/qg-logs/pr-lint.log` e fixar manualmente. `// eslint-disable-next-line` so com causa raiz documentada.

### `build` -- compilacao / parse

Se o projeto tem `tsconfig.json`: o gate gera um tsconfig EFEMERO (`.qg-tsconfig.json`) no dir-alvo que faz `extends` do `nodejs/rules/tsconfig.base.json` do QG e roda `npx --yes -p typescript tsc -p .qg-tsconfig.json`. O `tsconfig.json` do projeto-alvo e IGNORADO (tamper-resistance: rodamos `-p <efemero>`, nunca `-p tsconfig.json`). Conta erros `error TSXXXX:`.

O ruleset do QG (`tsconfig.base.json`) e **strict travado porem JSX/React-Native-capaz**: `jsx: preserve` faz o `tsc` parsear arquivos `.tsx`/`.jsx` sem cuspir `TS17004`/`TS6142` fantasma (o bug do my-project: 293 erros fantasma num projeto que compila limpo). Um shim ambiente (`rules/qg-jsx-shim.d.ts`) declara um `JSX.IntrinsicElements` permissivo SO como fallback global -- se o projeto fornece `@types/react` no `node_modules`, os tipos reais do React vencem; sem isso, evita `TS7026`/`TS2875` fantasma. **Strictness vem do QG; o dev nao afrouxa** (`strict:false` no tsconfig do projeto e ignorado). O numero de build errors reflete erros de tipo REAIS, nao ausencia de `--jsx`.

Fallback: se o projeto pinou um TypeScript antigo (< 5.0, sem `moduleResolution: bundler`), o gate detecta `TS5023/TS5095/TS6046` e re-roda com `moduleResolution: node` (ainda strict, ainda JSX).

Senao (sem `tsconfig.json`): roda `node --check` em cada `.js`/`.mjs`/`.cjs` (excluindo `node_modules`, `coverage`, `dist`). Conta arquivos com exit code != 0.

**Como interpretar regressao:** Em TS, erro de tipagem ou sintaxe REAL (o gate nao gera mais ruido de JSX). Em JS, syntax error. Pouco provavel passar pelo dev e chegar no gate.

### `test` -- testes falhando

Se `package.json` tem `scripts.test`: roda `npm test --silent`. Senao: roda `node --test` (built-in).

Conta o numero N do resumo `ℹ fail N` (node:test) OU `# fail N` (TAP de jest/vitest) OU `Tests: ... N failed,` (jest summary).

**Tool error vs regressao:** se o runner trava ou panica antes do summary, nao gera linha de fail -- nao conta. Esses casos aparecem no log e o usuario precisa investigar.

**Como interpretar regressao:** testes que passavam falham agora. Solucao: rodar localmente `node --test` (ou `npm test`), ler erro, fixar.

`test.skip()`/`describe.skip()` eh proibido como mitigacao (ver [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- complexidade ciclomatica

Roda `npx --yes eslint --no-config-lookup --rule '{"complexity":["error",15]}' .`. Conta funcoes com `has a complexity of N` no output.

**Threshold:** `15` (mesmo da metrica equivalente em Go/Rust para consistencia entre linguagens).

**Como interpretar regressao:** PR introduziu funcao acima do threshold. Solucoes: extrair sub-funcoes; substituir cadeias `if/else` por dispatch object/Map; usar early-return.

### `coverage` -- cobertura de linhas

Roda `npx --yes c8 --reports-dir=<tmp> --reporter=json-summary node --test` e extrai `.total.lines.pct` do `coverage-summary.json`.

**Margem de tolerancia:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Como interpretar regressao:** PR adicionou codigo sem teste correspondente. Solucoes: adicionar teste cobrindo o caminho novo; ou (com criterio) aumentar margem em `.qg.yaml`.

## Troubleshooting comum

### `npx` esta lento na primeira execucao

`npx --yes <pkg>` faz download da primeira vez e cache em `~/.npm/_npx`. A segunda execucao eh instantanea. Se voce precisa de reproducibilidade exata (CI), considere instalar `prettier`, `eslint`, `c8` como `devDependencies` no projeto -- `npx` vai usar a versao local automaticamente.

### `eslint` exige flat config (v9+) e o projeto nao tem

O gate detecta presence de config (`eslint.config.*` ou `.eslintrc.*`); se ausente, usa `--no-config-lookup` com regra minima embutida. Para desabilitar essa heuristica, adicione `eslint.config.js` no projeto:

```js
export default [{ files: ['**/*.js'], rules: { 'no-unused-vars': 'error' } }];
```

### Baseline cache stale apos mudar branch base

```bash
~/.quality-gate/nodejs/qg.sh --base origin/main --refresh-baseline
# OU
rm -rf /tmp/qg-baseline-nodejs
```

### `git archive` falha com "fatal: not a valid object name"

A base ref nao existe localmente. Solucao:

```bash
git fetch origin
```

## Metricas omitidas

Nenhuma. Node.js suporta as 6 metricas reservadas via prettier/eslint/tsc/node-test/c8.

## Metricas extras

Nenhuma em V1. Candidatos futuros:
- `audit` via `npm audit --audit-level=moderate` -- vulnerabilidades em deps.
- `bundle_size` via `bundlesize` ou `size-limit` -- tamanho do output.
- `type_coverage` via `typescript-coverage-report` -- % de codigo sem `any`.

Para adicionar, seguir contrato (secao "Estender") e `.claude/skills/add-quality-gate/`.
