# Race Gate (project rule, outranks AGENTS.md in Kilo precedence)

Read RACE-GATE.md. A turn ending in prose is invalid.
Any `/v1/models*` observation must be recorded as Buffered | SseCorrupted | Sse | Absent in config/notebook.json before use.
Any completion call must record reasoning-passthrough behaviour in config/notebook.json.
Any >4s operation goes through `scripts/race-run.sh`.
