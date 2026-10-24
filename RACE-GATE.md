# RACE-GATE — Framing-Aware Discovery + Run-Scoped Narration Guard + Semantic Brake

RG-1. A turn terminates only as: ToolCall(receipt) | RaceTuple | Fork | CredentialArtifactDetected | ProviderFlagged(reason) | BLOCKED/ABSENT(reason). Prose is not a constructor.

RG-2. Model discovery is framing-aware. `GET /v1/models*` is probed for Buffered vs SSE.
      A `text/event-stream` response on `/v1/models` is `SseCorrupted` (OpenShell #1772), not a discovery win.
      Downstream code branches on the recorded framing; never assume.

RG-3. Narration guard is run-scoped, not message-scoped. Accumulate tool calls per `runId`.
      Action-promise keywords + zero tools across the run = violation. Escalate WARN -> CRITICAL; clear on success.

RG-4. Semantic brake: five detectors (semantic similarity, action repetition, n-gram overlap, edit distance, compression distance).
      KILL on repetition across reasoning text AND tool-call JSON, not just final answer.

RG-5. Reasoning replay: persist `reasoning_content` when the endpoint honours it (X-Reasoning-Passthrough).
      Never send a tool-loop request with an empty prior. Re-inject the compacted ledger {turn, claim, evidence, next}.

RG-6. On repetition, force a cold-tool re-rank: list tools not used in the last N turns whose descriptions match the current subgoal.
      Models over-select recent tools (EMNLP 2026); the fork must surface the cold candidate explicitly.

RG-7. Provider flags -> ProviderFlagged(reason) -> fallback chain. Never narrate, never evade.
