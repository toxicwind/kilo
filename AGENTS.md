# AGENTS.md — ranch/kappa monorepo (master project)

> **Refines:** `/home/toxic/estate/AGENTS.md` (the estate control-plane). Asserts
> **"refines, never contradicts"** the estate contract above it. A shallow root
> here + per-subproject AGENTS.md where each repo owns its rules.

## Mission

Single entry point for all Kappa work on this host. Owns the relationship
between the three subprojects, the main-binary build, and the system-shell
integration. Everything lands here or in a subproject below — never ad-hoc
scratch.

## Subprojects (git submodules)

| Subproject | Path | Origin | Owns |
|---|---|---|---|
| Kappa Code (engine) | `kappa-code/` | `Kilo-Org/kilo-code` → `toxicwind/kappa-code` | CLI/TUI/agent runtime (fork of opencode). Monorepo with 20+ packages. **Fork feature: browser-fingerprint HTTP transport** (`HttpOptions.fingerprint`). Build: `make` / `make:nativelink` / `kmake-test` tmux grid. |
| Kappa CLI repo | `kappa-cli/` | `Kilo-Org/kilo-cli` → `toxicwind/kappa-cli` | Full upstream mirror, pinned `6f08110d4`. Bump via `FORKS.md` procedure. |
| Kappa × ble.sh | `kappa-ble/` | local (system integration, `ranch/kappa/kappa-ble`) | ble.sh first-class integration: `contrib/kappa.bash` (+`contrib/kappa/tooling.bash`), `\q{contrib/kappa-info}` prompt unit, `Ctrl-x k`. |

Always work inside the subproject's own checkout (`ranch/kappa/<name>`) and let
each subproject's nested `AGENTS.md` own its rules.

## Building the main `kappa` binary

In `kappa-code/`:

- `bun run make` — install + build single binary → `dist/@kappacode/*/bin/kappa`.
- `bun run make:nativelink` — same, using the estate build daemon (mise remote
  cache at `127.0.0.1:25148`). `BUN_BUILD_REMOTE_CACHE` is dead code — bun does
  not support it; the mise `[task_config.cache]` section is the SSOT.
- Deploy target on this box: `/usr/lib/kappa/kappa`.

Kappa pack the CLI: `KAPPA_SKIP_BUNDLED_BWRAP=1 bun run --cwd packages/cli
script/build.ts --single` (skip `--skip-install` only after a clean
`bun install`).

Note: the vendored checkout may lack build tooling (husky/vite/tsgo/
node-gyp-build). That is a checkout-infra gap, not a feature defect — repair the
toolchain, do not monkeypatch around it.

## Running tests

Use the tmux grid so the estate 2s shim (which SIGKILLs >2s `bun test` in
interactive shells) cannot kill the run:

```
kmake-test start    # 4-pane grid; per-pane full output to ~/.local/state/kappa/kmake/pane-*.{log,err}
kmake-test status   # scrape the panes
kmake-test kill
```

All pane commands write full output to files — no `2>&1`, no `|tail`, no
`/dev/null` (kairos guard).

## Rules (estate + guard doctrine)

- **The guard must be followed.** Never merge streams (`2>&1`), never swallow
  output (`/dev/null`), never truncate (`| head|tail`), never blocking-`sleep`.
  Persistent full output; read via `ffs`. Race a faster alternative or
  `forge borrow` on a guard breach — do not retry the same command.
- **Additive only.** The box is live. Never disable a peer/daemon.
- **Secrets** from the keyring (`ranch/secretsmith`) or `~/.secrets`, never
  committed. Keyed provider options use `{env:…}`.
- **`kappacode_change` markers** on shared opencode files; Kappa-specific code in
  `*kappacode*` dirs needs none. Run `check-opencode-annotations` after edits.
- **Verify before claiming complete** — fresh command, exit code, evidence.
- **Push to canonical main.** Never force-push without `backup/main-<date>`.
  Never push to `evmts`/`corral`.
- `repository-quality-gate-fixer` and the SDD prompt trio live in
  `ranch/repository-quality-gate-fixer`; keep their gates green before merge.
- **Follow the vibe meta-todo** (root AGENTS.md): race faster with borrow +
  papers during the task; after research spawn the next 6 complex todos.