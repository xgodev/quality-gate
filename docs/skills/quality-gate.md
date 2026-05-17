# quality-gate

This plugin **is** the Quality Gate. The `quality-gate` skill calls the bundled **dispatcher** (`${CLAUDE_PLUGIN_ROOT}/qg`), which detects the project's language(s) 100% in shell (zero AI), runs the matching `<lang>/qg.sh` gate(s), parses the JSON verdict, and renders an analyzed result in PT-BR before the developer opens a PR. The dispatcher and the per-language scripts ship inside this plugin (under `${CLAUDE_PLUGIN_ROOT}`) — no runtime clone.

Language detection is **no longer the skill's (or the AI's) responsibility** — the dispatcher owns it. The skill only invokes `qg` and interprets the JSON.

## How to invoke

- Explicit triggers (PT preserved verbatim for routing): "rodar quality gate", "rodar QG", "rodar gate", "rodar o gate", "verificar qualidade", "checar qualidade antes do PR", "validar antes do PR", "esta pronto para PR", "qa antes do push".
- EN equivalents: "run quality gate", "run QG", "check quality before PR".
- Auto-trigger: when the user says "vou abrir PR" / "abrir PR agora" / "vamos fazer push", the skill offers to run the gate first (and asks if it's already been run).

## Walkthrough — quality gate before opening a PR

User: `rodar quality gate`.

1. **Locate the dispatcher.** The gate is bundled in this plugin: the dispatcher lives at `${CLAUDE_PLUGIN_ROOT}/qg` (no runtime clone or pull; it updates with the plugin). `QG_PATH` overrides the path for local gate development.
2. **Detect `--base`**, in order: `git symbolic-ref refs/remotes/origin/HEAD`, `origin/main`, `origin/master`, `origin/develop`. None exist -> run in **absolute mode** (omit `--base`) or ask the user; never `HEAD~1`.
3. **Run the dispatcher with `--format json`** into a timestamped `--log-dir` (never `<lang>/qg.sh` directly — detection is the dispatcher's job):

   ```bash
   "$GATE_PATH/qg" \
     --base origin/main \
     --format json \
     --log-dir /tmp/qg-<timestamp> \
     > /tmp/qg-<timestamp>/result.json \
     2> /tmp/qg-<timestamp>/stderr.log
   ```

4. **Map the exit code:**
   - `0` -> `passed`/`bypassed`/fast-path/absolute-no-violation. Render green.
   - `1` -> `regressed` (comparative) or `failed` (absolute threshold violated). Render table + analysis.
   - `2` -> tool/setup error / missing prereq / invalid `.qg.yaml`. Relay `stderr.log` literally; do NOT interpret the JSON; do NOT install the prereq; stop.
   - `3` -> **no supported language detected** (dispatcher-exclusive). Report "open an issue / use `add-quality-gate`"; do NOT improvise an ad-hoc gate.
5. **Interpret the JSON.** Single language -> the `<lang>/qg.sh` object directly. N languages / monorepo -> envelope `{ aggregate_verdict, results:[...] }` (iterate `.results[]`). Field `mode` is `comparative` (`{name,base,pr,delta,verdict}`) or `absolute` (`{name,value,threshold,verdict}`, `base_ref:null`).
6. **Render in PT-BR with analysis.** For every regressed/violated metric, read the matching `pr-<metric>.log` / `abs-<metric>.log`, cite `file:line`, suggest a specific fix.
7. **Behavior by verdict:** `passed` -> green + "OK pra abrir PR" (no `gh pr create`); `regressed`/`failed` -> table with analysis, offers to help fix, no `QG_BYPASS_REASON` suggestion; `bypassed` -> warning with declared reason + audit-log reminder.

## Common questions / gotchas

- **Bypass is never the skill's decision.** Under pressure (hotfix), the skill confirms the reason in writing and orients the user to set `QG_BYPASS_REASON` in their own shell. Never sets it for them.
- **Skill never edits code/tests/config to "make it pass".** No fake assert-true tests, no `#[ignore]`, no `extra_fast_path_paths` to hide the regression.
- **Editing the project's quality config (`.eslintrc`, `clippy.toml`, `.stylelintrc`) is both forbidden and useless** — the gate enforces its own ruleset (tamper-resistance) and ignores the project's config by default.
- **Skill never runs `gh pr create` / `git push` / `--no-verify` / `--force` after any verdict.** Green is a signal, not an action.
- **Exit 3 (no supported language)** -> stop, point to the issue tracker / `add-quality-gate`. No ad-hoc gate, no `<lang>/qg.sh` written into the project.
- **Exit 2 (tool error)** -> relay literally; do not interpret the JSON; do not install prerequisites yourself; suggest the command and wait.
- **Always call the dispatcher `qg`, not `<lang>/qg.sh`.** Use `<lang>/qg.sh` only if the user explicitly asks to debug one gate.

## Files / templates / references

- Skill: [`../skills/quality-gate/SKILL.md`](../skills/quality-gate/SKILL.md)
- Gate is bundled in this plugin (dispatcher `qg` + per-language scripts + contract under `${CLAUDE_PLUGIN_ROOT}`).
- Contract reference (bundled in the plugin): `${CLAUDE_PLUGIN_ROOT}/docs/contract.md` (dispatcher, tamper-resistance, `.qg.yaml projects:`), `${CLAUDE_PLUGIN_ROOT}/docs/output-format.md` (monorepo envelope), `${CLAUDE_PLUGIN_ROOT}/docs/consume.md`.

## Limitations (V1)

- Supported languages: source of truth is the "Linguagens suportadas" table in the gate repo's `README.md`. Today: Rust, Go, Python, Node.js, Java, Swift, Kotlin, and **Web (HTML/CSS static)**. The `web` gate measures only `fmt`+`lint` and only fires when there is no `package.json` (React/Vue/etc. with `package.json` = a nodejs project).
- Detection is 100% the dispatcher's (`qg --detect`); the skill keeps no sentinel table.
- The gate updates with the plugin (`claude plugin update` / auto-update); no runtime clone/cache. `QG_PATH` overrides for local gate development.
- The skill does not install gate prerequisites. On exit code 2, it relays the gate's instruction.
