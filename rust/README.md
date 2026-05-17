# Quality Gate -- Rust

Quality gate for Rust projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `cargo` (Rust toolchain -- install via [rustup.rs](https://rustup.rs))
- `cargo-llvm-cov` -- `cargo install cargo-llvm-cov`
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

## Usage

```bash
~/.quality-gate/rust/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `cargo fmt --check` | `Diff in` lines |
| `lint` | `cargo clippy -D warnings` (without complexity) | `^error` lines |
| `build` | `cargo build --all-targets` | `^error` lines |
| `test` | `cargo test --all-targets --no-fail-fast` | sum of `failed: N` |
| `complexity` | `cargo clippy -W cognitive_complexity/too_many_lines/too_many_arguments/type_complexity` | matches |
| `coverage` | `cargo llvm-cov --json` | `lines.percent` |

Complexity thresholds: clippy community defaults (cognitive 25, lines 100, args 7, type 250).

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean Rust project.
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions.

## Details and troubleshooting

See [`docs/languages/rust.md`](../docs/languages/rust.md).

## Tests for the script itself

```bash
bats tests/rust-qg.bats
```
