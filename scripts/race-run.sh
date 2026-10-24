#!/usr/bin/env bash
set -euo pipefail
SCRIPT="${1:?usage: race-run.sh <script> [seconds] [log]}"
SECS="${2:-8}"; LOG="${3:-/tmp/kappa-race-$(date +%Y%m%d-%H%M%S).log}"
/home/toxic/estate/bin/delend-code-race-line "$SCRIPT" --seconds "$SECS" --log "$LOG"
printf '\nRACE_RECEIPT log=%s\n' "$LOG"
