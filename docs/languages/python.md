# Quality Gate -- Python

Documentacao especifica do gate Python. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Python assume **pip + pyproject.toml** como build/deps padrao. Nao suporta poetry, uv, pdm em V1 (a sentinela so checa `pyproject.toml`/`setup.py`/`setup.cfg`/`requirements*.txt` -- compativel com qualquer um, mas as ferramentas-canonica do gate -- `ruff`, `pytest`, `radon` -- sao instaladas via `pip`).

A sentinela de presenca eh um destes na raiz: `pyproject.toml`, `setup.py`, `setup.cfg` ou `requirements*.txt`. Se nenhum existir no baseline, gate emite warning e sai 0.

## Pre-requisitos com instalacao

### macOS

```bash
brew install python jq
pip install ruff pytest pytest-cov radon
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install python3 python3-pip jq
pip install ruff pytest pytest-cov radon
```

Garanta que `~/.local/bin` (ou o `bin` do venv ativo) esta no `$PATH`.

## Metricas -- o que cada uma mede em Python

### `fmt` -- formatacao

Roda `ruff format --check .`. Conta linhas `Would reformat: <path>` (cada arquivo desformatado eh uma linha).

**Configuracao:** se o projeto tem `pyproject.toml` com `[tool.ruff]`, eh respeitado. Sem ele, defaults do ruff (formato proximo de Black).

**Como interpretar regressao:** PR introduziu arquivo desformatado. Solucao: `ruff format .`.

### `lint` -- ruff check

Roda `ruff check --output-format=concise .`. Conta linhas no formato `path:linha:col: CODIGO mensagem` (cada issue eh uma linha).

**Configuracao:** se o projeto tem `[tool.ruff.lint]` em `pyproject.toml`, eh respeitado. Sem ele, defaults do ruff (regras E + F do pyflakes/pycodestyle).

**Como interpretar regressao:** PR introduziu issue que ruff detecta. Solucao: rodar `ruff check --fix .` (auto-fix simples) ou ler `target/qg-logs/pr-lint.log` e fixar manualmente. Se for falso positivo, `# noqa: <CODIGO>` com causa raiz documentada.

### `build` -- compilacao bytecode

Roda `python3 -m compileall -q .`. Conta linhas `*** ...` ou `SyntaxError:` (cada erro de sintaxe eh contado).

Em Python "build" eh sintaxe valida + import-able; nao ha linker. compileall faz parse + bytecode de todos os `.py`.

**Como interpretar regressao:** sintaxe quebrada. Pouco provavel passar pelo dev e chegar no gate; geralmente conflito de merge.

### `test` -- testes falhando

Roda `pytest -p no:cacheprovider --tb=no -q`. Conta linhas `^FAILED ` no resumo do pytest.

`-p no:cacheprovider` evita criar `.pytest_cache` no fixture. `--tb=no -q` mantem o log enxuto -- so resumo.

**Tool error vs regressao:** se pytest falha por erro de coleta (import error em `conftest.py`, plugin quebrado), o exit code eh != 0 e nao gera linha `FAILED ` -- nao conta como teste falhado. Esses casos aparecem no log e o usuario precisa investigar.

**Como interpretar regressao:** testes que passavam falham agora. Solucao: `pytest -x --tb=short`, ler erro, fixar.

`@pytest.mark.skip` eh proibido como mitigacao (ver [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- complexidade ciclomatica

Roda `radon cc -n C -s .`. Conta funcoes em grau C (cc >= 11) ou pior.

**Threshold:** `C` no radon corresponde a complexidade ciclomatica >= 11 (escala A=1-5, B=6-10, C=11-20, D=21-30, E=31-40, F>=41).

**Como interpretar regressao:** PR introduziu funcao com cc >= 11. Solucoes: extrair sub-funcoes; substituir cadeias `if/elif` por dispatch dict ou polymorphism; usar early-return.

### `coverage` -- cobertura de linhas

Roda `pytest --cov=. --cov-report=json:<path>` e extrai `.totals.percent_covered` via `jq`.

**Margem de tolerancia:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Como interpretar regressao:** PR adicionou codigo sem teste correspondente. Solucoes: adicionar teste cobrindo o caminho novo; ou (com criterio) aumentar margem em `.qg.yaml` se for caso justificado.

## Troubleshooting comum

### `pytest-cov` nao instalado, gate sai 2

```bash
pip install pytest-cov
```

O gate detecta `pytest-cov` via `python3 -c "import pytest_cov"` (modulo, nao binario).

### `ruff` ausente

```bash
pip install ruff
# OU
brew install ruff   # macOS
```

### Baseline cache stale apos mudar branch base

```bash
~/.quality-gate/python/qg.sh --base origin/main --refresh-baseline
# OU
rm -rf /tmp/qg-baseline-python
```

### `git archive` falha com "fatal: not a valid object name"

A base ref nao existe localmente. Solucao:

```bash
git fetch origin
```

## Metricas omitidas

Nenhuma. Python suporta as 6 metricas reservadas com ferramentas oficiais.

## Metricas extras

Nenhuma em V1. Candidatos futuros:
- `type` via `mypy --strict` -- erros de tipagem.
- `security` via `bandit -q -r .` -- issues de seguranca.
- `vuln` via `pip-audit` -- vulnerabilidades em dependencias.

Para adicionar, seguir contrato (secao "Estender") e `.claude/skills/add-quality-gate/`.
