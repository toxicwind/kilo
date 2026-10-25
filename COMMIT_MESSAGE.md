feat(gate): framing-aware discovery + run-scoped narration guard + semantic brake + anti-flail runtime

This commit installs the complete flail gate system for kappa-code:

## Files Added

### Core Gate Configuration
- `config/gate.json` - Gate thresholds (proseTokenBudget, pivotBudget, repetitionJaccard, etc.)
- `config/notebook.json` - In-memory ledger for framing, reasoning passthrough, loop/narration tendency
- `RACE-GATE.md` - Doctrine: RG-1 through RG-7 (turn constructors, framing-aware discovery, narration guard, semantic brake, reasoning replay, cold-tool re-rank, provider flags)
- `.kilo/rules/race-gate.md` - Project rule outranking AGENTS.md

### Scripts
- `scripts/notebook.ts` - Atomic read/modify/write ledger over config/notebook.json
- `scripts/fuzz-models.ts` - Framing-aware model discovery (Buffered | SseCorrupted | Sse | Absent | Error)
- `scripts/probe-completions.ts` - Measures reasoning passthrough, loop tendency (n-gram Jaccard), narration tendency
- `scripts/narration-guard.ts` - Run-scoped narration guard + semantic brake + cold-tool re-rank
- `scripts/race-run.sh` - Wrapper for delend-code-race-line
- `scripts/kappa_sse_recon.sh` - Dynamic model discovery + SSE endpoint fuzzing + agentic patch via tau -p
- `scripts/kappa_anti_flail.sh` - Anti-flail runtime with loop detection, circuit breaker, dynamic model routing

### Reports
- `FLAIL-REPORT.md` - Framing verdict (Buffered on /models), model fingerprints, measured rates, gate thresholds

## Key Features Implemented

1. **Framing-Aware Discovery (FAD)**: Probes `/v1/models*` matrix, classifies responses as Buffered/SseCorrupted/Sse/Absent/Error per OpenShell #1772
2. **Run-Scoped Narration Guard (RSNG)**: Tracks action-promise regex + zero tools across runId, escalates WARN→CRITICAL
3. **Semantic Brake**: Five detectors (semantic, action, ngram, edit, compression) on reasoning + tool-call JSON
4. **Reasoning Replay Ledger (RRL)**: Persists reasoning_content when endpoint honors X-Reasoning-Passthrough
5. **Cold-Tool Re-rank**: Forces orthogonal fork + surfaces tools not used in last N turns (EMNLP 2026)
6. **Anti-Flail Runtime**: Dynamic model discovery, per-model latency routing, tool-call fingerprint loop detection, per-tool circuit breaker

## Probe Results (from notebook.json)
- Framing verdict: Buffered on `/models` (200, application/json, 3296 bytes)
- minimax-m3: reasoning_passthrough=false, selfNgram=0, narration=0
- glm-5.3-flash: reasoning_passthrough=false, selfNgram=0, narration=0
- Gate thresholds remain at defaults (selfNgram ≤ 0.5, no narration violations)