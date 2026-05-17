# Quality Gate -- Rust

Rust-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Rust assumes **Cargo** (official). It does not support xargo, standalone miri, or others.

## Prerequisites with install

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

## Metrics -- what each one measures in Rust

### `fmt` -- formatting

Runs `cargo fmt --all -- --check`. Counts lines starting with `Diff in `, which indicate a file diverging from the rustfmt config.

**Configuration:** if the project has a `rustfmt.toml` at the root, it is respected. Without it, rustfmt defaults.

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `cargo fmt --all`.

### `lint` -- clippy

Runs `cargo clippy --all-targets -- -D warnings -A clippy::cognitive_complexity -A clippy::too_many_lines -A clippy::too_many_arguments -A clippy::type_complexity`. Counts `^error[E0XXX]:` and `^error:` lines.

The 4 complexity lints are silenced here (measured separately in `complexity`).

**How to interpret a regression:** the PR introduced a new warning (with `-D warnings`, a warning becomes an error). Fix: read `target/qg-logs/pr-lint.log`, identify the lint, decide between a code fix or `#[allow(...)]` with a documented root cause.

### `build` -- compilation

Runs `cargo build --all-targets`. Counts `^error` lines.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate; usually indicates a merge conflict or an incomplete refactor.

### `test` -- failing tests

Runs `cargo test --all-targets --no-fail-fast`. Sum of `failed: N` across all test binaries.

**How to interpret a regression:** tests that passed on the baseline fail on the PR. Fix: run locally `cargo test --workspace --no-fail-fast`, read the error, fix it.

`#[ignore]` is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- cyclomatic/cognitive complexity

Runs `cargo clippy --all-targets -- -A clippy::all -W clippy::cognitive_complexity -W clippy::too_many_lines -W clippy::too_many_arguments -W clippy::type_complexity`. Counts matches of the 4 lints.

**Thresholds (clippy community defaults, NOT custom):**
- `cognitive_complexity`: 25
- `too_many_lines`: 100
- `too_many_arguments`: 7
- `type_complexity`: 250

**How to interpret a regression:** the PR introduced a function above some threshold. Fixes: break it into smaller functions, extract intermediate structs, simplify branches.

### `coverage` -- line coverage

Runs `cargo llvm-cov --json --output-path X` and extracts `.data[0].totals.lines.percent` via `jq`.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test covering the new path; or (with discretion) raise the margin in `.qg.yaml` if the case is justified.

## Common troubleshooting

### `cargo-llvm-cov` very slow or hangs

Old versions had bugs in large monorepos. Update:

```bash
cargo install cargo-llvm-cov --force
```

### Stale baseline cache after changing the base branch

```bash
~/.quality-gate/rust/qg.sh --base origin/main --refresh-baseline
```

or

```bash
rm -rf /tmp/qg-baseline-rust
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

None. Rust supports the 6 reserved metrics with official tools.

## Extra metrics

None in V1. Future candidates:
- `audit` via `cargo audit` -- vulnerabilities in dependencies.
- `unsafe_count` via `cargo geiger` -- use of `unsafe` blocks.

To add, follow the contract (section "Extending") and `skills/add-quality-gate/`.
