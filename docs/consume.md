# Como usar o Quality Gate no seu projeto

Este guia cobre uso **local** (dev na máquina). CI será documentado em V2.

## Pré-requisitos

1. Git, bash 4+, awk, tar (sistema).
2. Pré-reqs específicos da linguagem do seu projeto. Ver [`languages/`](languages/).

Para Rust: cargo, cargo-llvm-cov, jq.

## Setup (uma vez por máquina)

```bash
git clone git@github.com:xgodev/quality-gate.git ~/.quality-gate
```

Atualize quando o time de plataforma anunciar mudanças:

```bash
git -C ~/.quality-gate pull --ff-only
```

## Rodar manualmente

No diretório do seu projeto:

```bash
~/.quality-gate/rust/qg.sh --base origin/main
```

Ou setando env vars:

```bash
QG_BASE_REF=origin/main ~/.quality-gate/rust/qg.sh
```

### Opções comuns

```bash
# Tolerância de coverage diferente (default 1.0pp)
~/.quality-gate/rust/qg.sh --base origin/main --cov-margin 0.5

# Re-extrair baseline (ignorar cache)
~/.quality-gate/rust/qg.sh --base origin/main --refresh-baseline

# Forçar gate completo (pular fast-path)
~/.quality-gate/rust/qg.sh --base origin/main --force-full

# Output JSON para parsing
~/.quality-gate/rust/qg.sh --base origin/main --format json > result.json
```

## Hook git pre-push (opcional)

Adicionar em `.git/hooks/pre-push`:

```bash
#!/usr/bin/env bash
exec ~/.quality-gate/rust/qg.sh --base origin/main
```

```bash
chmod +x .git/hooks/pre-push
```

## Config por repo (`.qg.yaml` opcional)

No raiz do seu projeto:

```yaml
cov_margin: 2.0
skip_metrics:
  - metric: complexity
    reason: "legacy module, plano de refactor em INT-1234"
    until: "2026-09-01"
extra_fast_path_paths:
  - "^vendor/"
```

Regras completas: [`contract.md`](contract.md#config-por-repo-qgyaml-opcional).

## Bypass de emergência

Hotfix de produção 3am, baseline quebrado, etc.:

```bash
QG_BYPASS_REASON="INT-9999 hotfix prod down, baseline corrompido" \
  ~/.quality-gate/rust/qg.sh --base origin/main
```

Bypass é registrado em `target/qg-logs/bypass.log`. Use com critério.

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| `::error::--base é obrigatório` | Não passou base ref | Adicionar `--base origin/main` |
| `::error::cargo-llvm-cov não encontrado` | Pré-req faltando | `cargo install cargo-llvm-cov` |
| Gate vermelho em PR que não tocou Rust | Fast-path não acionou | Ver se algum `Cargo.*` ou `.rs` foi modificado |
| Baseline cache stale | Cache divergente | `--refresh-baseline` ou `rm -rf /tmp/qg-baseline-*` |
| `git archive` falhou | Ref não existe local | `git fetch origin` |

Detalhes por linguagem em [`languages/<lang>.md`](languages/).

## Smoke test (validação manual)

Para confirmar que a instalação funciona end-to-end:

```bash
# Clone do gate
git clone git@github.com:xgodev/quality-gate.git ~/.quality-gate

# Teste 1: baseline contra ele mesmo → deve sair 0 (passed)
cd ~/.quality-gate/rust/test-fixtures/baseline
~/.quality-gate/rust/qg.sh \
  --base origin/main \
  --baseline-dir "$(pwd)" \
  --force-full
echo "Esperado: exit 0"

# Teste 2: regressed contra baseline → deve sair 1 (regressed)
cd ~/.quality-gate/rust/test-fixtures/regressed
~/.quality-gate/rust/qg.sh \
  --base origin/main \
  --baseline-dir ~/.quality-gate/rust/test-fixtures/baseline \
  --force-full
echo "Esperado: exit 1, 5 métricas regredidas"

# Teste 3: bypass governado → deve sair 0 com warning
QG_BYPASS_REASON="smoke test" ~/.quality-gate/rust/qg.sh \
  --base origin/main \
  --baseline-dir ~/.quality-gate/rust/test-fixtures/baseline \
  --force-full
echo "Esperado: exit 0, ::warning:: visível, audit log gravado"
```

Se os 3 testes saírem com os exit codes esperados, a instalação está OK.
