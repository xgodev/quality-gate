# Formatos de Output

Detalha os dois formatos de saída do gate (texto e JSON) com exemplos completos por veredito.

Para a especificação canônica, ver [`contract.md`](contract.md). Este documento é referência operacional.

## Texto (default)

### Veredito: passou

```
═══ Quality Gate — rust ═══
  branch:        feature/INT-1234
  base ref:      origin/main
  baseline:      /tmp/qg-baseline-rust
  cov margin:    1.0pp
  logs:          target/qg-logs/

── medindo base ──
── medindo PR ──

métrica       base       pr     veredito
─────────────────────────────────────────
fmt              0        0    ✅ same
lint             3        2    ✅ improved
build            0        0    ✅ same
test fails       0        0    ✅ same
complexity       7        7    ✅ same
coverage     82.3%    82.5%   ✅ improved

::notice::PR não regrediu nenhuma métrica.
```

Exit code: 0.

### Veredito: regrediu

```
[header igual...]

métrica       base       pr     veredito
─────────────────────────────────────────
fmt              0        2    ❌ regressed
lint             3        5    ❌ regressed
build            0        0    ✅ same
test fails       0        1    ❌ regressed
complexity       7        9    ❌ regressed
coverage     82.3%    79.8%   ❌ regressed (margem: 1.0pp, queda: 2.5pp)

::error::PR regrediu fmt, lint, test fails, complexity, coverage — ver acima.
```

Exit code: 1.

### Veredito: bypassed

```
═══ Quality Gate — rust ═══
  branch:        hotfix/INT-9999
  base ref:      origin/main

::warning::QG bypass ativo — motivo: INT-9999 hotfix prod down, baseline corrompido
::warning::Esta execução não validou métricas. Audit log: target/qg-logs/bypass.log
```

Exit code: 0. Métricas não medidas.

### Veredito: fast-path

```
═══ Quality Gate (fast-path) ═══
  branch:        docs/atualiza-readme
  base ref:      origin/main
  scope:         no Rust files touched → skipping cargo gates
  override:      QG_FORCE_FULL=1 to run full gate

── arquivos modificados ──
  README.md
  docs/getting-started.md

✅ fast-path passed (no Rust to measure)
```

Exit code: 0.

## JSON (`--format json`)

### Veredito: passou

```json
{
  "schema_version": "1.0",
  "language": "rust",
  "branch": "feature/INT-1234",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 1142,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "lint", "base": 3, "pr": 2, "delta": -1, "verdict": "improved" },
    { "name": "build", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "test", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "complexity", "base": 7, "pr": 7, "delta": 0, "verdict": "same" },
    { "name": "coverage", "base": 82.3, "pr": 82.5, "delta": 0.2, "margin": 1.0, "verdict": "improved" }
  ]
}
```

Exit code: 0. Stdout recebe SÓ o JSON; mensagens de progresso vão para stderr.

### Veredito: regrediu

Idêntico ao "passou", mas `verdict: "regressed"` global e métricas com `verdict: "regressed"`. Exit code: 1.

### Veredito: bypassed

```json
{
  "schema_version": "1.0",
  "language": "rust",
  "branch": "hotfix/INT-9999",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 0,
  "verdict": "bypassed",
  "bypass_reason": "INT-9999 hotfix prod down, baseline corrompido",
  "metrics": []
}
```

Exit code: 0. `metrics` vazio (gate não mediu).

### Veredito: fast-path

```json
{
  "schema_version": "1.0",
  "language": "rust",
  "branch": "docs/atualiza-readme",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 2,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": []
}
```

Exit code: 0. `metrics` vazio (fast-path).

## Modo absoluto (`--base` ausente)

Sem `--base`/`QG_BASE_REF` o gate roda em modo absoluto: mede `.` uma vez, sem baseline, sem coluna `base`.

### Texto — com `absolute_thresholds` (uma violação)

```
═══ Quality Gate — rust (modo absoluto) ═══
  branch:        feature/x
  cov margin:    n/a (modo absoluto)
  logs:          target/qg-logs/

── medindo (sem baseline) ──

métrica       valor   limite   veredito
─────────────────────────────────────────
fmt              0        0    ✅ ok
lint             3        0    ❌ violated
build            0        0    ✅ ok
test fails       0        0    ✅ ok
complexity       7        -    ℹ️  reported
coverage     82.3%      80%    ✅ ok

::error::PR violou thresholds absolutos: lint — ver acima.
```

Exit code: 1.

### Texto — sem `.qg.yaml` / sem thresholds

Todas as linhas viram `ℹ️  reported`, rodapé:

```
::notice::modo absoluto sem thresholds — apenas relatório (exit 0)
```

Exit code: 0.

### JSON — modo absoluto sem thresholds

```json
{
  "schema_version": "1.1",
  "mode": "absolute",
  "language": "rust",
  "branch": "feature/x",
  "base_ref": null,
  "started_at": "2026-05-15T10:00:00Z",
  "duration_seconds": 120,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "lint", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "build", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "test", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "complexity", "value": 7, "threshold": null, "verdict": "reported" },
    { "name": "coverage", "value": 82.3, "threshold": null, "verdict": "reported" }
  ]
}
```

Exit code: 0.

### JSON — modo absoluto com threshold violado

```json
{
  "schema_version": "1.1",
  "mode": "absolute",
  "language": "rust",
  "branch": "feature/x",
  "base_ref": null,
  "started_at": "2026-05-15T10:00:00Z",
  "duration_seconds": 120,
  "verdict": "failed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "value": 0, "threshold": 0, "verdict": "ok" },
    { "name": "lint", "value": 3, "threshold": 0, "verdict": "violated" },
    { "name": "build", "value": 0, "threshold": 0, "verdict": "ok" },
    { "name": "test", "value": 0, "threshold": 0, "verdict": "ok" },
    { "name": "complexity", "value": 7, "threshold": 10, "verdict": "ok" },
    { "name": "coverage", "value": 82.3, "threshold": 80, "verdict": "ok" }
  ]
}
```

Exit code: 1.

## `--detect`

`<lang>/qg.sh --detect` imprime só o slug e exit 0 se a sentinela existe na raiz; nada + exit 1 caso contrário.

```
$ rust/qg.sh --detect
rust
$ echo $?
0
```

## Dispatcher `qg` (monorepo / multi-linguagem)

O dispatcher `qg` da raiz roda 1..N gates. Com **1 linguagem** detectada, a
saida e exatamente a do `<lang>/qg.sh` (single object — sem wrapper). Com **N
linguagens** (ou `.qg.yaml projects:` com multiplos paths), `--format json`
emite um array envelopado:

```json
{
  "schema_version": "1.1",
  "aggregate_verdict": "regressed",
  "results": [
    {
      "schema_version": "1.1",
      "mode": "comparative",
      "language": "go",
      "branch": "feature/INT-1234",
      "base_ref": "origin/main",
      "started_at": "2026-05-15T10:00:00Z",
      "duration_seconds": 88,
      "verdict": "passed",
      "bypass_reason": null,
      "metrics": [
        { "name": "fmt", "base": 0, "pr": 0, "delta": 0, "verdict": "same" }
      ]
    },
    {
      "schema_version": "1.1",
      "mode": "comparative",
      "language": "nodejs",
      "branch": "feature/INT-1234",
      "base_ref": "origin/main",
      "started_at": "2026-05-15T10:01:28Z",
      "duration_seconds": 142,
      "verdict": "regressed",
      "bypass_reason": null,
      "metrics": [
        { "name": "lint", "base": 3, "pr": 5, "delta": 2, "verdict": "regressed" }
      ]
    }
  ]
}
```

- `aggregate_verdict` = pior dos `results[].verdict` (precedencia de exit:
  `2 > 1 > 3 > 0`; ou seja `failed`/`regressed` vence `passed`).
- Exit code do dispatcher = pior exit code dos gates rodados.
- **0 linguagens detectadas** → stderr `::error::nenhuma linguagem suportada
  detectada`, **exit 3**, nenhum JSON em stdout.

Texto (`--format text`): cada gate imprime seu proprio bloco em sequencia,
seguido de um rodape `::error::`/`::notice::` agregado.

```
$ qg --detect
go
nodejs
$ echo $?
0
```

## Display labels (texto vs JSON)

A coluna "métrica" no texto pode usar label humano (`test fails`) enquanto o JSON usa o `name` reservado (`test`). Mapeamento:

| `name` (JSON) | Display label (texto) |
|---|---|
| `fmt` | `fmt` |
| `lint` | `lint` |
| `build` | `build` |
| `test` | `test fails` |
| `complexity` | `complexity` |
| `coverage` | `coverage` |

Display label fica a cargo da linguagem mas DEVE ser estável entre runs.

## Logs detalhados

Independente do `--format`, cada etapa de medição grava log completo em `<log-dir>/`:

- `<log-dir>/base-fmt.log`
- `<log-dir>/base-lint.log`
- `<log-dir>/base-build.log`
- `<log-dir>/base-test.log`
- `<log-dir>/base-complexity.log`
- `<log-dir>/base-coverage.json`
- `<log-dir>/pr-fmt.log` ... `<log-dir>/pr-coverage.json`
- `<log-dir>/bypass.log` (se bypass acionado)

Logs são reset a cada execução do mesmo `<log-dir>`.
