#!/usr/bin/env bash
set -euo pipefail

export FREEINFERENCE_API_KEY="hyi-u5H98cHTgYz_bTWcZMW0373Sl_ytJzRVCmTFSJXtJqs"
cd /home/toxic/pens/olympus/products/kappa

# Get list of models from the catalog
MODELS=$(bun scripts/fuzz-models.ts 2>&1 | jq -r '.probes[] | select(.verdict=="Buffered") | .note' | head -1 | python3 -c '
import json, sys
data = sys.stdin.read()
import re
ids = re.findall(r'"id":"([^"]+)"', data)
for id in ids:
    print(id)
')

echo "Models found: $MODELS"

# Run probe-completions for each model
for model in $MODELS; do
    echo "=== Probing $model ==="
    FI_MODEL="$model" bun scripts/probe-completions.ts 2>&1
done