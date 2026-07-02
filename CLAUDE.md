# CLAUDE.md — quality-gate

This repo is **`quality-gate`**: a self-contained Claude Code plugin that
**is** the Quality Gate — the dispatcher `qg`, the per-language gates
(`<lang>/qg.sh`), the bundled `quality-gate` skill, the contract docs, and
the canonical rulesets. It is also usable as a plain CLI in CI (clone the
repo, run `./qg`); `.claude-plugin/` is inert outside Claude Code.

These are hard rules learned the expensive way. Read them before touching
anything so a future session does not repeat past mistakes.

## Hard rules

- **Docs are ALWAYS updated in the same change. No exceptions.** Any change
  to code, structure, dependencies, behavior, or version updates — in the
  **same commit** — every doc it affects: `README.md`, `CONTRIBUTING.md`,
  `docs/**`, this `CLAUDE.md`, per-language `README.md`/`docs/languages/*`,
  the skill `SKILL.md`s, and `.claude-plugin/plugin.json` `description` if it
  no longer matches reality. A doc or manifest that lies about the project is
  a defect, not a follow-up. Before committing, ask: "what does this change
  make false?" — and fix it now, not later.
- **English only. Everywhere.** README, CONTRIBUTING, `docs/**`, `CLAUDE.md`,
  `SKILL.md`, code comments, AND all runtime output (`::error::`,
  `::warning::`, `::notice::`, the metric table, every user-facing string in
  `<lang>/qg.sh` and `<lang>/lib/*.sh`). This is a public OSS project — there
  is no Portuguese anywhere. (An earlier internal context mandated PT-BR;
  that does **not** apply here and must not be reintroduced.)
- **Zero proprietary / internal references.** No `carrefour`, `bitbucket`,
  internal project names, internal billing tables, internal hostnames,
  internal repo URLs — in code, docs, history, or examples. Before any push:
  `grep -ri -E 'carrefour|bitbucket|<internal-names>' . --include='*' | grep -v '\.git/'`
  must be empty. Examples use generic names (`my-project`, `origin/main`).
- **The plugin is self-contained — no runtime clone/pull/cache.** The skill
  invokes the dispatcher at `${CLAUDE_PLUGIN_ROOT}/qg` (override only via the
  `QG_PATH` env var for local gate development). Never reintroduce a
  `~/.<x>-quality-gate` clone + `git pull` cache: it caused staleness,
  divergence, version desync, and repoint churn. The gate updates *with the
  plugin*.
- **Tamper-resistance is law (all languages).** The gate ships and enforces
  its **own** rulesets under `<lang>/rules/`. Project quality configs
  (`.eslintrc`, `clippy.toml`, `.stylelintrc`, `tsconfig.json`, `detekt.yml`,
  `ruff.toml`, …) are **ignored by default** — invoke each tool pointing at
  the QG ruleset with the flags that suppress project-config discovery. The
  only override is the `QG_RULESET_DIR` env var supplied by **whoever runs
  the gate** (CI/operator) — **never** read from a project file
  (`.qg.yaml`/repo), because the dev controls that and could weaken it.
- **fmt/lint/complexity measure SOURCE, not generated output.** A canonical,
  QG-owned ignore list (`node_modules/ dist/ build/ out/ .next/ coverage/
  *.min.js *.bundle.js …`) is always applied; never the project's
  `.eslintignore`/`.prettierignore`. Generated/vendored dirs must not inflate
  metrics.
- **The project's declared toolchain/build-system is authoritative.** If the
  declared package manager / build system / pinned toolchain cannot be
  honored exactly (tool absent, unsupported build system, pinned version not
  satisfiable), that is a **tool-error → exit 2** with a clear message —
  **never** silently substitute a different tool (no npm fallback for a
  `yarn.lock`, no `mvn` for a Gradle project, no system gradle ignoring
  `./gradlew`, etc.). Silent substitution measures the wrong artifact.
- **Every "tool missing" error teaches how to install it.** Format:
  `::error::<cause> -- install: '<linux cmd>' (Linux) / '<macOS cmd>' (macOS) (<consequence if ignored>)`.
- **Tool-error (exit 2) ≠ regression (exit 1).** A segfault/ICE/OOM/missing
  dep is exit 2, never a `build` regression. Never mask an infra failure as a
  code problem.
- **Numeric sanitization before `jq --argjson`/arithmetic.** Every metric
  value passes through `_num` (non-numeric/empty/"Unknown" → `0`). A raw
  non-number into `jq --argjson` crashes the whole gate.
- **Exit codes:** `0` pass/bypassed/fast-path/absolute-no-violation; `1`
  regressed (comparative) or failed (absolute threshold) or `--detect` no
  sentinel; `2` setup/tool error; `3` dispatcher: no supported language.
  `--base` absent is **not** an error — it is absolute mode.
- **Contract changes are additive and backward-compatible.**
  `QG_CONTRACT_VERSION` stays `1`. `schema_version` bumps only for JSON
  schema changes; the validator accepts older `schema_version` values.
- **Plugin version discipline (3 files move together).** Any change to the
  plugin/skill bumps `.claude-plugin/plugin.json` `version`, the README
  version line, AND a `CHANGELOG.md` entry — in the **same commit**. Verify
  before committing; a manifest that lies about its version is a defect.
- **Templates use `{{UPPER_SNAKE}}` placeholders only.** No `<lower>`,
  `${VAR}`, `[NAME]`. Identifiers, filenames, and command examples are ASCII
  — no accents, no em-dash (use `--`).
- **Detection is 100% shell, zero AI.** The dispatcher `qg` resolves
  language(s) via `<lang>/qg.sh --detect`. No hardcoded sentinel table in any
  skill/markdown. Monorepo: `.qg.yaml projects:` (hybrid root + declared
  sub-projects); multiple languages run all, aggregate (worst verdict wins).
- **Adding a language is the `add-quality-gate` skill's job**, never an
  ad-hoc gate in the target project. New language ships with its own
  `<lang>/rules/`, `--detect`, absolute mode, dep resolution, `_num`, and
  bats incl. tamper + generated-dir-exclusion + toolchain-authoritative
  tests.

## Common mistakes

- Reintroducing the runtime clone/cache "because the skill needs the gate" —
  the gate **is** the plugin; use `${CLAUDE_PLUGIN_ROOT}`.
- Reading the project's lint/format config "to respect the project" — that
  defeats the gate. Ship and enforce the QG ruleset.
- Counting errors in `build/`/`dist/`/minified bundles — exclude generated
  dirs via the QG-owned ignore.
- `tsc` without `--jsx`/realistic strict base for React/TS — use the QG
  `tsconfig.base.json` (strict but JSX/RN-capable).
- Bumping `plugin.json` and forgetting README/CHANGELOG (or vice-versa).
- Leaving any Portuguese string (run a language sweep before push).
- Guessing Claude Code plugin specifics — verify (claude-code-guide / docs)
  before asserting.
- Declaring `"hooks": "./hooks/hooks.json"` in `plugin.json` — the standard
  `hooks/hooks.json` is auto-loaded; a manifest reference to it is a
  DUPLICATE and makes the whole plugin fail to load ("Duplicate hooks file
  detected", broke v0.3.0). `manifest.hooks` is only for additional,
  non-standard hook files. Doc-verified forms are not runtime-verified: any
  change to plugin registration (manifest keys, hooks, skills layout) must be
  smoke-tested in a real Claude Code session before release.
