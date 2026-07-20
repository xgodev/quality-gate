# Quality Gate -- Rust

Quality gate for Rust projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `cargo` (Rust toolchain -- install via [rustup.rs](https://rustup.rs))
- `cargo-llvm-cov` -- `cargo install cargo-llvm-cov`
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

## Usage

```bash
~/.claude-plugin/tools/quality-gate/rust/qg.sh --base origin/main
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

## Diff scoping

By default the gate measures only the workspace packages a diff affects
(changed packages + their in-workspace reverse-dependents), on both the PR and
the baseline, instead of recompiling the whole workspace twice. An untouched
crate's examples are never built, and coverage instruments only affected
packages. A diff to a root-level file (`Cargo.lock`, root `Cargo.toml`,
`rust-toolchain*`, `.cargo/config*`, root `build.rs`) or `--force-full` /
`QG_FORCE_FULL=1` falls back to the full workspace. See
[`docs/languages/rust.md`](../docs/languages/rust.md#scope----the-gate-measures-what-the-pr-changed).

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/scope.sh`](lib/scope.sh) -- diff-to-package resolution and reverse-dep closure.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`../lib/changed-files.sh`](../lib/changed-files.sh) -- shared changed-file union (all gates).
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean Rust project.
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions.

## Details and troubleshooting

See [`docs/languages/rust.md`](../docs/languages/rust.md).

## Tests for the script itself

```bash
bats tools/quality-gate/tests/rust-qg.bats
```
