# Contribuindo com o Quality Gate

## Princípios

1. **Independência por linguagem.** Cada `<lang>/qg.sh` é standalone. Sem orquestrador, sem `lib/` compartilhado entre linguagens.
2. **Contrato é lei.** Toda mudança que afete CLI, exit codes, output ou config passa por revisão do `docs/contract.md` antes do código.
3. **PT-BR no output.** Mensagens, ::error::, ::warning::, headers de tabela em PT-BR. Identificadores e nomes de métricas em EN ASCII.
4. **TDD obrigatório** para mudanças no script. Test fixtures em `<lang>/test-fixtures/baseline/` e `<lang>/test-fixtures/regressed/`.

## Adicionar nova linguagem

### Com IA (recomendado)

Invoque a skill `add-quality-gate` (em `.claude/skills/add-quality-gate/`):

```
adicionar quality gate para Go
```

A skill segue checklist obrigatório de 22 passos. Não pular nenhum.

### Manual (sem IA)

Siga o mesmo checklist documentado em `.claude/skills/add-quality-gate/SKILL.md`.

## Mudar o contrato

1. Atualizar `docs/contract.md` + `docs/contract-v1.schema.json`.
2. Atualizar TODOS os `<lang>/qg.sh` para cumprir a nova versão.
3. Bumpar `QG_CONTRACT_VERSION` no header de cada script.
4. Atualizar test fixtures se a mudança afeta output.
5. Atualizar `.claude/skills/add-quality-gate/SKILL.md` se afeta o processo.

Mudança breaking → bumpar major (v1 → v2). V1 ainda não tem versionamento via tags (decisão deliberada do spec).

## Estrutura do repo

```
quality-gate/
├── README.md
├── CONTRIBUTING.md
├── docs/
│   ├── contract.md
│   ├── contract-v1.schema.json
│   ├── output-format.md
│   ├── consume.md
│   └── languages/<lang>.md
├── .claude/skills/add-quality-gate/
└── <lang>/
    ├── qg.sh
    ├── README.md
    └── test-fixtures/{baseline,regressed}/
```

## Testes do próprio gate

`tests/` na raiz contém testes em [bats](https://github.com/bats-core/bats-core). Rodar:

```bash
bats tests/
```

Toda mudança em `<lang>/qg.sh` exige test correspondente em `tests/<lang>-qg.bats`.
