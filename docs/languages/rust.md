# Quality Gate -- Rust

Rust-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Run it with Docker (recommended)

```bash
docker run --rm -v "$PWD:/src" -w /src \
  ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
```

The image carries the gate and the whole rust toolchain -- nothing to install. It is detected by `Cargo.toml`. `/src` must be the checkout **with its `.git`** (the baseline uses `git archive <base>`); in GitHub Actions set `fetch-depth: 0`. Omit `--base` for absolute mode.

The gate scopes cargo to the workspace packages your diff touches (plus their in-workspace reverse-dependents), so wall-clock tracks the diff, not the whole workspace. The two crate-layout metrics are the exception: they scan the whole workspace's files on both sides, which costs no build and keeps an untouched crate contributing the same number to base and PR.

See the [README](../../README.md) for tags, exit codes, flags and CI snippets. The sections below describe what each metric measures and how to run the script directly, without the image.

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

Runs `cargo fmt --all -- --check --config-path <QG>/rust/rules/rustfmt.toml` (full scope) or the same with `-p <pkg> ...` (narrowed). Counts lines starting with `Diff in `, which indicate a file diverging from the rustfmt config.

**Configuration:** the gate enforces **its own** ruleset and the project's config is ignored (see the "Tamper-resistance" section of [`../contract.md`](../contract.md)). `--config-path` points at `<QG>/rust/rules/rustfmt.toml`, so the project's `rustfmt.toml` does not affect the verdict; clippy likewise reads `clippy.toml` from `CLIPPY_CONF_DIR=<QG>/rust/rules`, never from the project. To predict the verdict locally, pass the same `--config-path`.

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `cargo fmt --all -- --config-path <quality-gate>/rust/rules/rustfmt.toml` -- a plain `cargo fmt --all` formats to *your* config and can leave the gate red.

### `lint` -- clippy

Runs `cargo clippy <scope> -- -D warnings --force-warn clippy::cognitive_complexity --force-warn clippy::too_many_lines --force-warn clippy::too_many_arguments --force-warn clippy::type_complexity` (`<scope>` = `--all-targets` full, or `-p <pkg> ... --lib --bins --tests` narrowed, with a separate `--examples` pass for touched packages only). Counts `^error[E0XXX]:` and `^error:` lines.

The 4 complexity lints stay at **warn** level here, so they are reported without being counted as lint errors -- the same invocation yields the `complexity` count (one clippy run per side instead of two; see `complexity`). `--force-warn` is what keeps them warnings: a plain `-W` does not, because the `warnings` group of `-D warnings` outranks a per-lint level whatever the flag order.

**How to interpret a regression:** the PR introduced a new warning (with `-D warnings`, a warning becomes an error). Fix: read `target/qg-logs/pr-lint.log`, identify the lint, decide between a code fix or `#[allow(...)]` with a documented root cause.

### `build` -- compilation

Runs `cargo build --all-targets` (full) or `cargo build -p <pkg> ... --lib --bins --tests` plus a `--examples` pass for touched packages (narrowed). Counts `^error` lines.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate; usually indicates a merge conflict or an incomplete refactor.

### `test` -- failing tests

Runs `cargo test --all-targets --no-fail-fast`. Sum of `failed: N` across all test binaries.

**How to interpret a regression:** tests that passed on the baseline fail on the PR. Fix: run locally `cargo test --workspace --no-fail-fast`, read the error, fix it.

`#[ignore]` is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- cyclomatic/cognitive complexity

Counts matches of the 4 lints in the **same** `cargo clippy` invocation that measures `lint` (see `lint` for the exact flags and scope); the matching lines are also written to `target/qg-logs/<side>-complex.log`. One clippy run per side measures both metrics: a second pass with different lint flags changes `CLIPPY_ARGS`, which is part of cargo's fingerprint, so it would recompile the whole scope.

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

### `codegen_mix` -- codegen mixed with hand-written code

Scans files, never compiles: one `cargo metadata --no-deps` plus a read of each
workspace member's `.rs` files. Counts the crates that **both** have a build
script calling a known codegen entry point (`slint_build::`, `tonic_build`,
`tonic_prost_build`, `prost_build`, `bindgen::`, `cxx_build::`, `capnpc::`,
`lalrpop` -- the list is `codegen_entry_points` in
`<QG>/rust/rules/crate-layout.toml`) **and** hold hand-written code beyond a
`lib.rs` that merely includes the generated output.

"Merely includes" means comments, inner attributes, `use`/`extern crate`, and
the include macros (`slint::include_modules!()`, `tonic::include_proto!`,
`include!(concat!(env!("OUT_DIR"), ...))`) with their continuation lines.
Anything else -- a `mod`, a function, a type -- is hand-written code sharing the
crate with the generator.

**Why it is a metric:** a crate is Rust's unit of incremental compilation.
Editing one hand-written line in a crate that also generates Rust recompiles the
generated code too, every time.

**How to interpret a regression:** the PR added hand-written code to a codegen
crate, or gave a codegen build script to a crate that already had modules.
`target/qg-logs/pr-layout.log` names the crate. Fix: keep the codegen crate down
to its `build.rs` + the include, and move the hand-written modules into a crate
that **depends** on it.

### `crate_size` -- oversized crates

The same single file scan. Sums, over every workspace member, the hand-written
lines **above** `max_hand_written_lines` (`<QG>/rust/rules/crate-layout.toml`,
5000 by default); a crate under the limit contributes 0.

Counting only the excess is what makes it a ratchet: a crate that is already
over the limit reads the same number on both sides and passes, a crate crossing
the limit goes from 0 to N, and growing an already-oversized crate goes from N
to N+k. Shrinking one is an improvement.

Not counted as a crate's weight, because each is its own compilation unit or is
not hand-written: `tests/`, `benches/`, `examples/`, `build.rs`, `tests.rs`,
`#[cfg(test)]` module bodies, files marked generated by the language's own
convention (a `@generated` / `Code generated ... DO NOT EDIT.` header, as
prost/tonic emit), and anything owned by a nested workspace member.

**Configuration:** both metrics read **only** the QG ruleset. There is no
`.qg.yaml` key for the limit -- the developer controls that file and a raised
limit would switch the check off. The single override is the `QG_RULESET_DIR`
env var, supplied by whoever RUNS the gate (see the "Tamper-resistance" section
of [`../contract.md`](../contract.md)). In absolute mode `.qg.yaml
absolute_thresholds` accepts `codegen_mix` and `crate_size` like any other
metric.

**How to interpret a regression:** a crate crossed the limit or grew past it.
`target/qg-logs/pr-layout.log` names it with its line count. Fix: split it along
an area boundary into crates that depend on each other.

## Common troubleshooting

### `cargo-llvm-cov` very slow or hangs

Old versions had bugs in large monorepos. Update:

```bash
cargo install cargo-llvm-cov --force
```

### Stale baseline cache after changing the base branch

```bash
./quality-gate/rust/qg.sh --base origin/main --refresh-baseline
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

## Quick mode (`--quick`)

Defers `coverage` only. `coverage` is a whole instrumented build plus a second test run under `cargo llvm-cov`. `complexity` is NOT deferred: it comes out of the same `cargo clippy` invocation that measures `lint`, so deferring it would discard a number the gate measured anyway. `codegen_mix` and `crate_size` are NOT deferred either: they are a file scan (one `cargo metadata` plus a read of the members' `.rs` files), so deferring them would save nothing.

A deferred metric is reported as `skipped` with no numbers and cannot fail the
run; the JSON carries `"quick": true` and `schema_version: "1.2"`. Never in CI
-- see [`../contract.md`](../contract.md#quick-mode---quick).

## Parallel sides

The baseline and the PR are measured concurrently by default (from 4 usable
cores); the numbers are identical to a sequential run.

Rust-specific: if the operator sets `CARGO_TARGET_DIR`, both trees would share
one build dir -- and two checkouts of the same workspace produce the **same**
crate metadata hash, so each side would link the other's artifacts. The gate
gives each side its own dir under it (`.../qg-base`, `.../qg-pr`). The cargo
default (a per-tree `./target`) is already isolated and is left alone.

`--no-parallel` forces one side after the other -- see
[`../contract.md`](../contract.md#parallel-sides---parallel----no-parallel).

## Omitted metrics

None. Rust supports the 6 reserved metrics with official tools.

## Extra metrics

Two, both measured by one file scan and both ratchets like every other metric
(see their sections above):

| Name | Counts | Fails if |
|---|---|---|
| `codegen_mix` | crates mixing `build.rs` codegen with hand-written modules | PR > base |
| `crate_size` | hand-written lines above the per-crate limit, summed | PR > base |

Future candidates:
- `audit` via `cargo audit` -- vulnerabilities in dependencies.
- `unsafe_count` via `cargo geiger` -- use of `unsafe` blocks.

To add, follow the contract (section "Extending") and the process in [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md).
