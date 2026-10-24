# FLAIL-REPORT

## Framing verdict

Buffered on /models (200, application/json, 3296 bytes). Correct framing per OpenShell #1772; catalog trustworthy.

## Model fingerprint

- minimax-m3: reasoning passthrough not honored, selfNgram 0, narration 0
- glm-5.3-flash: reasoning passthrough not honored, selfNgram 0, narration 0

## Measured rates

- loop tendency (selfNgram): 0.0 (no repetition detected)
- narration tendency: 0 violations, 0 action promises across 5 runs

## Gate thresholds (argon-shaped)

- proseTokenBudget: 900 (unchanged, selfNgram <= 0.5)
- pivotBudget: 2 (unchanged)
- narration.escalateAfter: 1, criticalAfter: 3 (unchanged, no violations)
- repetitionJaccard: 0.82
