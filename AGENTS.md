# AGENTS.md — ranch/kilo monorepo (master project)

> Refines: none higher (self-contained master for the Kilo forks on this box).
> A shallow root here + per-subproject AGENTS.md where each repo owns its rules.

## Mission

Single entry point for all Kilo work on this host. Owns the relationship
between the three subprojects, the main-binary build, and the system-shell
integration. Everything lands here or in a subproject below — never ad-hoc
scratch.

## Subprojects (git submodules)

| Subproject | Path | Origin | Owns |
|---|---|---|---|
| Kilo Code (engine) | `kilo-code/` | `toxicwind/kilo-code.git` (fork of `Kilo-Org/kilo-code`) | CLI/TUI/agent runtime. Fork feature: browser-fingerprint HTTP transport (`HttpOptions.fingerprint`). Build: `make` / `make:nativelink` / `kmake-test` tmux grid. |
| Kilo CLI repo | `kilo-cli/` | `toxicwind/kilo-cli.git` (fork of `Kilo-Org/kilo-cli`) | Full upstream mirror, pinned `6f08110d4`. Bump via `FORKS.md` procedure. |
| Kilo × ble.sh | `kilo-ble/` | local (system integration, `file://…/ranch/kilo/kilo-ble`) | ble.sh first-class integration: `contrib/kilo.bash` (+`contrib/kilo/tooling.bash`), `\q{contrib/kilo-info}` prompt unit, `Ctrl-x k`. |

Always work inside the subproject's own checkout (`ranch/kilo/<name>`) and let
each subproject's nested `AGENTS.md` own its rules.

## Building the main `kilo` binary

In `kilo-code/`:

- `bun run make` — install + build single binary → `dist/@kilocode/*/bin/kilo`.
- `bun run make:nativelink` — same with `BUN_BUILD_REMOTE_CACHE` (needs the
  estate NativeLink REAPI at `127.0.0.1:25155`, started via pitchfork
  `estate/nativelink`).
- Deploy target on this box: `/usr/lib/kilo/kilo`.

Note: the vendored checkout may lack build tooling (husky/vite/tsgo/
node-gyp-build). That is a checkout-infra gap, not a feature defect — repair the
toolchain, do not monkeypatch around it.

## Running tests

Use the tmux grid so the estate 2s shim (which SIGKILLs >2s `bun test` in
interactive shells) cannot kill the run:

```
kmake-test start    # 4-pane grid; per-pane full output to /home/toxic/tmp/kilo-compact/kmake/pane-*.{log,err}
kmake-test status   # scrape the panes
kmake-test kill
```

All pane commands write full output to files — no `2>&1`, no `|tail`, no
`/dev/null` (two-sec guard).

## Rules (estate + guard doctrine)

- **The guard must be followed.** Never merge streams (`2>&1`), never swallow
  output (`/dev/null`), never truncate (`| head|tail`), never blocking-`sleep`.
  Persistent full output; read via `ffs`. Race a faster alternative or
  `forge borrow` on a guard breach — do not retry the same command.
- **Additive only.** The box is live. Never disable a peer/daemon.
- **Secrets** from the keyring (`ranch/secretsmith`) or `~/.secrets`, never
  committed. Keyed provider options use `{env:…}`.
- **`kilocode_change` markers** on shared opencode files; Kilo-specific code in
  `*kilocode*` dirs needs none. Run `check-opencode-annotations` after edits.
- **Verify before claiming complete** — fresh command, exit code, evidence.
- **Push to canonical main.** Never force-push without `backup/main-<date>`.
  Never push to `evmts`/`super-ralph`.
- `repository-quality-gate-fixer` and the SDD prompt trio live in
  `ranch/repository-quality-gate-fixer`; keep their gates green before merge.