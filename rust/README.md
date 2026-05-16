# Quality Gate — Rust

Gate de qualidade para projetos Rust. Cumpre o [contrato v1](../docs/contract.md).

## Pré-requisitos

- `cargo` (toolchain Rust — instale via [rustup.rs](https://rustup.rs))
- `cargo-llvm-cov` — `cargo install cargo-llvm-cov`
- `jq` — `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (sistema)

## Uso

```bash
~/.quality-gate/rust/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Métricas medidas

| Métrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `cargo fmt --check` | linhas `Diff in` |
| `lint` | `cargo clippy -D warnings` (sem complexity) | linhas `^error` |
| `build` | `cargo build --all-targets` | linhas `^error` |
| `test` | `cargo test --all-targets --no-fail-fast` | soma de `failed: N` |
| `complexity` | `cargo clippy -W cognitive_complexity/too_many_lines/too_many_arguments/type_complexity` | matches |
| `coverage` | `cargo llvm-cov --json` | `lines.percent` |

Thresholds de complexidade: defaults da comunidade clippy (cognitive 25, lines 100, args 7, type 250).

## Estrutura

- [`qg.sh`](qg.sh) — script principal.
- [`lib/measure.sh`](lib/measure.sh) — funções `count_*` e `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) — render texto e JSON.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) — projeto Rust limpo.
- [`test-fixtures/regressed/`](test-fixtures/regressed/) — projeto com regressões deliberadas.

## Detalhes e troubleshooting

Ver [`docs/languages/rust.md`](../docs/languages/rust.md).

## Testes do próprio script

```bash
bats tests/rust-qg.bats
```
