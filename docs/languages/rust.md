# Quality Gate — Rust

Documentação específica do gate Rust. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Rust assume **Cargo** (oficial). Não suporta xargo, miri standalone, ou outros.

## Pré-requisitos com instalação

### macOS

```bash
# Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Coverage tool
cargo install cargo-llvm-cov

# JSON parser
brew install jq
```

### Linux (Ubuntu/Debian)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install cargo-llvm-cov
sudo apt install jq
```

## Métricas — o que cada uma mede em Rust

### `fmt` — formatação

Roda `cargo fmt --all -- --check`. Conta linhas iniciando com `Diff in `, que indicam arquivo divergente da config rustfmt.

**Configuração:** se o projeto tem `rustfmt.toml` na raiz, é respeitado. Sem ele, defaults do rustfmt.

**Como interpretar regressão:** PR introduziu arquivo desformatado. Solução: `cargo fmt --all`.

### `lint` — clippy

Roda `cargo clippy --all-targets -- -D warnings -A clippy::cognitive_complexity -A clippy::too_many_lines -A clippy::too_many_arguments -A clippy::type_complexity`. Conta linhas `^error[E0XXX]:` e `^error:`.

Os 4 lints de complexidade são silenciados aqui (medidos separado em `complexity`).

**Como interpretar regressão:** PR introduziu warning novo (com `-D warnings`, warning vira error). Solução: ler `target/qg-logs/pr-lint.log`, identificar lint, decidir entre fix de código ou `#[allow(...)]` com causa raiz documentada.

### `build` — compilação

Roda `cargo build --all-targets`. Conta linhas `^error`.

**Como interpretar regressão:** código não compila. Improvável passar pelo dev e chegar no gate; geralmente indica conflict de merge ou refactor incompleto.

### `test` — testes falhando

Roda `cargo test --all-targets --no-fail-fast`. Soma de `failed: N` em todos os binários de teste.

**Como interpretar regressão:** testes que passavam no baseline falham no PR. Solução: rodar localmente `cargo test --workspace --no-fail-fast`, ler erro, fixar.

`#[ignore]` é proibido como mitigação (ver [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` — complexidade ciclomática/cognitiva

Roda `cargo clippy --all-targets -- -A clippy::all -W clippy::cognitive_complexity -W clippy::too_many_lines -W clippy::too_many_arguments -W clippy::type_complexity`. Conta matches dos 4 lints.

**Thresholds (defaults da comunidade clippy, NÃO custom):**
- `cognitive_complexity`: 25
- `too_many_lines`: 100
- `too_many_arguments`: 7
- `type_complexity`: 250

**Como interpretar regressão:** PR introduziu função acima de algum threshold. Soluções: quebrar em funções menores, extrair structs intermediárias, simplificar branches.

### `coverage` — cobertura de linhas

Roda `cargo llvm-cov --json --output-path X` e extrai `.data[0].totals.lines.percent` via `jq`.

**Margem de tolerância:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Como interpretar regressão:** PR adicionou código sem teste correspondente. Soluções: adicionar test cobrindo o caminho novo; ou (com critério) aumentar a margem em `.qg.yaml` se for caso justificado.

## Troubleshooting comum

### `cargo-llvm-cov` muito lento ou trava

Versões antigas tinham bugs em monorepo grande. Atualize:

```bash
cargo install cargo-llvm-cov --force
```

### Baseline cache stale após mudar branch base

```bash
~/.quality-gate/rust/qg.sh --base origin/main --refresh-baseline
```

ou

```bash
rm -rf /tmp/qg-baseline-rust
```

### `git archive` falha com "fatal: not a valid object name"

A base ref não existe localmente. Solução:

```bash
git fetch origin
```

## Métricas omitidas

Nenhuma. Rust suporta as 6 métricas reservadas com ferramentas oficiais.

## Métricas extras

Nenhuma em V1. Candidatos futuros:
- `audit` via `cargo audit` — vulnerabilidades em dependências.
- `unsafe_count` via `cargo geiger` — uso de blocks `unsafe`.

Para adicionar, seguir contrato (seção 4.7) e `.claude/skills/add-quality-gate/`.
