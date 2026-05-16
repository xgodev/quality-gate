# Testes do Quality Gate

Testes em [bats](https://github.com/bats-core/bats-core).

## Rodar tudo

```bash
bats tests/
```

## Rodar só uma linguagem

```bash
bats tests/rust-qg.bats
```

## Estrutura

- `tests/<lang>-qg.bats` — testes do script de cada linguagem.
- `tests/helpers/setup.bash` — helpers compartilhados.
- `tests/contract.bats` — testes do contrato (válidos para QUALQUER linguagem).

## Fixtures

Cada `<lang>/test-fixtures/{baseline,regressed}/` é usado pelos testes via `qg_fixture_path "<lang>" "baseline"`.
