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

## Scope -- the gate measures what the PR changed

By default the gate does **not** recompile the whole workspace. It resolves the
set of workspace packages the diff affects -- the packages a changed file
belongs to, **plus their in-workspace reverse-dependents** (so a signature
change in a base crate still surfaces downstream build/test breakage) -- and
scopes every cargo command to that set with `-p <pkg>`. The baseline is measured
on the same set, intersected with the packages that exist on the base ref (a
package the PR adds reads base = 0, because it did not exist).

Consequences:
- Wall-clock is proportional to the diff, not to the (possibly huge,
  native-heavy) workspace.
- Coverage instruments only affected packages, so a large native tree no longer
  OOMs the linker.
- An untouched crate's **examples** are never built (examples compile only for
  the packages the diff actually touched), so a platform-specific example in an
  unrelated crate cannot gate your PR.

**Full-workspace triggers.** The gate measures the whole workspace when the diff
touches a root-level file that can affect everything -- `Cargo.lock`, the root
`Cargo.toml`, `rust-toolchain`/`rust-toolchain.toml`, `.cargo/config*`, a root
`build.rs` -- or when `--force-full` / `QG_FORCE_FULL=1` is set. The text and
JSON output always report the scope that was measured.

The commands below are shown in their full-workspace form; under a narrowed
scope, `--all` / `--all-targets` become `-p <pkg> ... --lib --bins --tests`.

## Metrics -- what each one measures in Rust

### `fmt` -- formatting

Runs `cargo fmt --all -- --check` (full scope) or `cargo fmt -p <pkg> ... -- --check` (narrowed). Counts lines starting with `Diff in `, which indicate a file diverging from the rustfmt config.

**Configuration:** if the project has a `rustfmt.toml` at the root, it is respected. Without it, rustfmt defaults.

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `cargo fmt --all`.

### `lint` -- clippy

Runs `cargo clippy <scope> -- -D warnings -A clippy::cognitive_complexity -A clippy::too_many_lines -A clippy::too_many_arguments -A clippy::type_complexity` (`<scope>` = `--all-targets` full, or `-p <pkg> ... --lib --bins --tests` narrowed, with a separate `--examples` pass for touched packages only). Counts `^error[E0XXX]:` and `^error:` lines.

The 4 complexity lints are silenced here (measured separately in `complexity`).

**How to interpret a regression:** the PR introduced a new warning (with `-D warnings`, a warning becomes an error). Fix: read `target/qg-logs/pr-lint.log`, identify the lint, decide between a code fix or `#[allow(...)]` with a documented root cause.

### `build` -- compilation

Runs `cargo build --all-targets` (full) or `cargo build -p <pkg> ... --lib --bins --tests` plus a `--examples` pass for touched packages (narrowed). Counts `^error` lines.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate; usually indicates a merge conflict or an incomplete refactor.

### `test` -- failing tests

Runs `cargo test --all-targets --no-fail-fast`. Sum of `failed: N` across all test binaries.

**How to interpret a regression:** tests that passed on the baseline fail on the PR. Fix: run locally `cargo test --workspace --no-fail-fast`, read the error, fix it.

`#[ignore]` is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- cyclomatic/cognitive complexity

Runs `cargo clippy <scope> -- -A clippy::all -W clippy::cognitive_complexity -W clippy::too_many_lines -W clippy::too_many_arguments -W clippy::type_complexity` (`<scope>` as in `lint`). Counts matches of the 4 lints.

**Thresholds (clippy community defaults, NOT custom):**
- `cognitive_complexity`: 25
- `too_many_lines`: 100
- `too_many_arguments`: 7
- `type_complexity`: 250

**How to interpret a regression:** the PR introduced a function above some threshold. Fixes: break it into smaller functions, extract intermediate structs, simplify branches.

### `coverage` -- line coverage

Runs `cargo llvm-cov --ignore-run-fail --json --output-path X` (adding `-p <pkg> ... --lib --bins --tests` under a narrowed scope) and extracts `.data[0].totals.lines.percent` via `jq`. The same invocation yields the `test` failure count -- one instrumented run per side, scoped so a large native tree does not OOM the linker.

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
~/.claude-plugin/tools/quality-gate/rust/qg.sh --base origin/main --refresh-baseline
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

To add, follow the contract (section "Extending") and the maintainer-only `add-quality-gate` skill (project-local, `.claude/skills/add-quality-gate/` in the gate repo).
