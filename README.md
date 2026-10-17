# Ranch Kilo Monorepo

Master project holding both Kilo forks on this box (awrawr-pc estate). This
superproject is the single entry point for Kilo work; it owns the relationship
between the CLI engine and the CLI tooling repo, and the build of the main
`kilo` binary.

## Subprojects

| Subproject | Path | Upstream | Notes |
|---|---|---|---|
| Kilo Code (engine) | `kilo-code/` | `Kilo-Org/kilo-code` → `toxicwind/kilo-code` | CLI/TUI/agent runtime (fork of opencode). Active dev. **Fork feature: browser-fingerprint HTTP transport.** |
| Kilo CLI repo | `kilo-cli/` | `Kilo-Org/kilo-cli` → `toxicwind/kilo-cli` | Full mirror, pinned `6f08110d4`. |

Both are registered as git submodules bound to the **local working forks** under
`ranch/kilo-code` and `ranch/kilo-cli`, so they appear here without a redundant
clone.

## Fork feature: browser-fingerprint HTTP transport

Kilo Code adds a browser TLS/HTTP2 fingerprint transport so the CLI can reach
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

When set, Kilo forwards with Chrome-aligned headers and a browser HTTP
signature (`sec-ch-ua`, `accept-language`, `sec-ch-ua-platform`, …) instead of
the runtime default. On Bun the native fetch already passes common Cloudflare
guards; this option guarantees the Chrome signature and is the mount point for
a stricter raw-TLS impersonator.

Implementation lives in Kilo Code:

- `packages/llm/src/schema/options.ts` — `HttpOptions.fingerprint` (option + merge)
- `packages/llm/src/route/transport/http.ts` — tags `x-kilo-fingerprint` on prepare
- `packages/llm/src/route/executor.ts` — strips marker, injects Chrome headers (kilocode_change)
- `packages/llm/test/executor.test.ts` — fixture-first coverage of the fingerprint path

## Building the main `kilo` binary

From the monorepo root (`/home/toxic/estate/ranch/kilo/kilo-code`):

```bash
bun install          # first time / after dep changes (long)
bun run --cwd packages/opencode script/build.ts --single --skip-install
```

Output: `packages/opencode/dist/*/*/bin/kilo` (scoped package output).
Deployed location on this box: `/usr/lib/kilo/kilo` (and the `kilo` shim).

## Rules

- Additive only (the estate box is live). Never disable a peer/daemon.
- Secrets come from the keyring (`ranch/secretsmith`), never committed.
- Edits that touch shared upstream opencode files carry `kilocode_change`
  markers (see `kilo-code/AGENTS.md`); Kilo-specific code lives in
  `packages/opencode/src/kilocode/` to keep upstream merges clean.