# Ranch Kappa Monorepo

Master project holding the kappa forks on this box (awrawr-pc estate). This
superproject is the single entry point for kappa work; it owns the relationship
between the CLI engine, the CLI tooling repo, and the build of the main
`kappa` binary.

## Subprojects

| Subproject | Path | Upstream | Notes |
|---|---|---|---|
| Kappa Code (engine) | `kappa-code/` | `Kilo-Org/kilo-code` → `toxicwind/kappa-code` | CLI/TUI/agent runtime (fork of opencode). Monorepo with 20+ packages. **Fork feature: browser-fingerprint HTTP transport.** |
| Kappa CLI repo | `kappa-cli/` | `Kilo-Org/kilo-cli` → `toxicwind/kappa-cli` | Full mirror, pinned `6f08110d4`. |
| Kappa × ble.sh | `kappa-ble/` | local (toxicwind system-integration) | First-class kappa integration for ble.sh (bash line editor): env-sanity fix, `\q{contrib/kappa-info}` prompt unit, `Ctrl-x k` launch. |

Both are registered as git submodules bound to the **local working forks** under
`ranch/kappa/kappa-code` and `ranch/kappa/kappa-cli`, so they appear here without a redundant
clone.

## Fork feature: browser-fingerprint HTTP transport

Kappa Code adds a browser TLS/HTTP2 fingerprint transport so the CLI can reach
Cloudflare-guarded inference providers (e.g. `freeinference.org` → Cloudflare
`403 1010` for non-browser signatures). Opt a provider in with a `fingerprint`
on its HTTP options:

```jsonc
{
  "provider": {
    "freeinference": {
      "type": "openai_compatible",
      "options": { "baseURL": "https://freeinference.org/v1" },
      "http": { "fingerprint": "chrome" }
    }
  }
}
```

When set, kappa forwards with Chrome-aligned headers and a browser HTTP
signature (`sec-ch-ua`, `accept-language`, `sec-ch-ua-platform`, …) instead of
the runtime default. On Bun the native fetch already passes common Cloudflare
guards; this option guarantees the Chrome signature and is the mount point for
a stricter raw-TLS impersonator.

Implementation lives in kappa Code:

- `packages/llm/src/schema/options.ts` — `HttpOptions.fingerprint` (option + merge)
- `packages/llm/src/route/transport/http.ts` — tags `x-kappa-fingerprint` on prepare
- `packages/llm/src/route/executor.ts` — strips marker, injects Chrome headers (kappacode_change)
- `packages/llm/test/executor.test.ts` — fixture-first coverage of the fingerprint path

## Fork feature: Flail Gate (model-agnostic loop/narration resilience)

Kappa Code ships a model-agnostic "flail gate" that stops agents from silently
flailing — repeating the same tool call, narrating instead of acting, or
re-deriving the same reasoning — regardless of which provider/model is served
(OpenCompatible, minimax-m3, qwen3.6-35b, argon, nemotron, kimi-k3, …). It
fingerprints what the endpoint actually does rather than trusting a vendor name.

Four self-contained pieces, integrated into the runtime:

- **Framing-aware discovery** — `GET /v1/models*` is probed for
  `Buffered | SseCorrupted | Sse | Absent` (OpenShell #1772); an SSE response on
  `/v1/models` is recorded as `SseCorrupted`, not a discovery win.
- **Run-scoped narration guard** — action-promise keywords + zero tool calls
  across a `runId` ⇒ violation; escalates and clears on success.
- **Semantic brake** — five detectors (semantic, action, n-gram, edit,
  compression) over the reasoning channel *and* tool-call JSON; on repetition it
  forces an orthogonal fork + cold-tool re-rank (EMNLP 2026).
- **Reasoning Replay Ledger** — persists `reasoning_content` when the endpoint
  honours it and re-injects the compacted `{turn, claim, evidence, next}` ledger.

Thresholds come from `config/gate.json` and `config/notebook.json` (measured
from live probes, never a vendor name). Integration points:

- `packages/cli/src/kappacode/flail-gate.ts` — gate orchestrator (Effect)
- `packages/cli/src/session/run-loop.ts` — run loop with the gate wired in
- `packages/core/src/config/gate.ts` + `packages/core/src/narration-guard.ts`
- `scripts/kappa_anti_flail.sh`, `scripts/kappa_sse_recon.sh` — probe/recon CLIs
- `packages/llm/test/anomaly-*.test.ts` — the 9 capability-contract tests (D-2026-10-23)

## Building the main `kappa` binary

From the monorepo root (`/home/toxic/pens/olympus/products/kappa/kappa-code`):

```bash
bun install          # first time / after dep changes (long)
KAPPA_SKIP_BUNDLED_BWRAP=1 bun run --cwd packages/cli script/build.ts --single --skip-install  # KAPPA_ prefix is the live name; omit the flag to bundle+pinned-hash the sandbox bwrap (release-grade)
```

Output: `packages/cli/dist/@kappacode/cli-linux-x64/bin/kappa` (scoped package output).
Deployed location on this box: `~/.local/bin/kappa` → kappa-code dist (per the estate bin
contract; the `kappa` shim and `/usr/lib/kappa/kappa` are the older root-installed copy).

## Monorepo packages (kappa-code)

```
packages/
├── core/              # Runtime: providers, plugins, config, sessions, models
├── cli/               # @kappacode/cli — the standalone CLI binary (`kappa`)
├── gateway/           # @kappacode/kappa-gateway — HTTP API gateway
├── vscode/            # @kappacode/vscode — VS Code extension
├── jetbrains/         # @kappacode/jetbrains — JetBrains plugin
├── console/           # @kappacode/kappa-console — settings UI
├── ui/                # @kappacode/ui — shared components
├── forge/             # Build daemon integration (estate forge :25148)
├── nativelink/        # Remote build cache (Nativlink RE API :25155)
├── secretsmith/       # Secret management (secretsmith keyring)
├── shims/             # System shims (git hooks, env fix, prompt units)
└── config/            # Configuration schemas & validation
```

## Rules

- Additive only (the estate box is live). Never disable a peer/daemon.
- Secrets come from the keyring (`ranch/secretsmith`), never committed.
- Edits that touch shared upstream opencode files carry `kappacode_change`
  markers (see `kappa-code/AGENTS.md`); kappa-specific code lives in
  `packages/opencode/src/kappacode/` to keep upstream merges clean.
