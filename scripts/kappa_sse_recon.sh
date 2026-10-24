#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---------------------------------------------------------
# Set these for your local environment.
: "${KAPPA_API_KEY:?Set KAPPA_API_KEY (your FreeInference/NVIDIA key)}"
: "${KAPPA_BASE_URL:=https://freeinference.org/v1}"
: "${KAPPA_SSE_PATH:=/chat/completions}"
: "${TAU_BIN:=tau}"
: "${TAU_MODEL:=${KAPPA_MODEL:-minimax-m3}}"
: "${SCOPE_NAME:=kappa}"

# Files for the in-memory-style arrays (bash 4+ associative arrays).
declare -A MODEL_REGISTRY=()
declare -A MODEL_SSE_STATUS=()
declare -a PROBE_ORDER=()
WORK_DIR="$(mktemp -d /tmp/kappa_sse_recon.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
LOG="$WORK_DIR/recon.log"
exec > >(tee -a "$LOG") 2>&1

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }

# --- 1. Discover models (dynamic, in-memory registry) ----------------------
log "Fetching model catalog from ${KAPPA_BASE_URL}/models ..."
MODELS_JSON="$(curl -fsS -H "Authorization: Bearer ${KAPPA_API_KEY}" \
  "${KAPPA_BASE_URL}/models")"

# Parse with jq; fall back to python3 if jq is absent.
if command -v jq >/dev/null 2>&1; then
  mapfile -t MODEL_IDS < <(jq -r '.data[]?.id // empty' <<<"$MODELS_JSON")
  while IFS=$'\t' read -r id obj; do
    [[ -n "$id" ]] && MODEL_REGISTRY["$id"]="$obj"
  done < <(jq -r '.data[]? | [.id, (tojson)] | @tsv' <<<"$MODELS_JSON")
else
  mapfile -t MODEL_IDS < <(python3 -c '
import json,sys
for m in json.load(sys.stdin).get("data",[]):
    print(m.get("id",""))
' <<<"$MODELS_JSON")
  while IFS=$'\t' read -r id obj; do
    [[ -n "$id" ]] && MODEL_REGISTRY["$id"]="$obj"
  done < <(python3 -c '
import json,sys
for m in json.load(sys.stdin).get("data",[]):
    print(m.get("id","")+"\t"+json.dumps(m))
' <<<"$MODELS_JSON")
fi

log "Discovered ${#MODEL_REGISTRY[@]} models."
PROBE_ORDER=("${MODEL_IDS[@]}")

# --- 2. Probe SSE endpoint per model (stream:true, minimal payload) --------
# We look for: HTTP 200 AND an SSE data: frame containing "chat.completion.chunk"
# and a terminating data: [DONE].
probe_sse() {
  local model="$1"
  local body
  body="$(python3 - "$model" <<'PY'
import json,sys
model=sys.argv[1]
print(json.dumps({
  "model": model,
  "messages": [{"role":"user","content":"Reply with the single word: ping"}],
  "max_tokens": 16,
  "stream": True,
  "temperature": 0
}))
PY
)"
  local tmp; tmp="$(mktemp "$WORK_DIR/probe.XXXXXX")"
  local code
  code="$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H "Authorization: Bearer ${KAPPA_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream" \
    -X POST "${KAPPA_BASE_URL}${KAPPA_SSE_PATH}" \
    -d "$body" || echo "000")"

  if [[ "$code" != "200" ]]; then
    MODEL_SSE_STATUS["$model"]="error:$code"
    log "  $model -> HTTP $code (no SSE)"
    return
  fi
  # Validate SSE shape: at least one data: chunk and a [DONE] sentinel.
  if grep -q '^data: ' "$tmp" && grep -q 'data: \[DONE\]' "$tmp"; then
    if grep -q 'chat\.completion\.chunk' "$tmp"; then
      MODEL_SSE_STATUS["$model"]="ok"
      log "  $model -> SSE OK"
    else
      MODEL_SSE_STATUS["$model"]="ok_no_chunk"
      log "  $model -> SSE present but no chat.completion.chunk"
    fi
  else
    MODEL_SSE_STATUS["$model"]="no_sse"
    log "  $model -> 200 but missing SSE data/[DONE]"
  fi
}

log "Probing SSE endpoint ${KAPPA_BASE_URL}${KAPPA_SSE_PATH} per model ..."
for id in "${PROBE_ORDER[@]}"; do
  probe_sse "$id"
done

# --- 3. Build a compact, actionable failure report -------------------------
REPORT="$WORK_DIR/failure_report.md"
{
  echo "# Kappa SSE Recon Failure Report"
  echo
  echo "- Base URL: \`${KAPPA_BASE_URL}\`"
  echo "- SSE path probed: \`${KAPPA_SSE_PATH}\`"
  echo "- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Model -> SSE status"
  echo
  echo "| Model | SSE Status |"
  echo "|---|---|"
  for id in "${PROBE_ORDER[@]}"; do
    echo "| \`${id}\` | ${MODEL_SSE_STATUS[$id]:-unknown} |"
  done
  echo
  echo "## Models with SSE OK"
  for id in "${PROBE_ORDER[@]}"; do
    [[ "${MODEL_SSE_STATUS[$id]}" == "ok" ]] && echo "- \`${id}\`"
  done
  echo
  echo "## Models WITHOUT usable SSE"
  for id in "${PROBE_ORDER[@]}"; do
    s="${MODEL_SSE_STATUS[$id]}"
    [[ "$s" != "ok" ]] && echo "- \`${id}\`: $s"
  done
  echo
  echo "## Raw probe log"
  echo '```'
  tail -n 120 "$LOG" 2>/dev/null || true
  echo '```'
} > "$REPORT"

log "Report written to $REPORT"

# --- 4. Agentic fix via tau -p ---------------------------------------------
# tau is given the concrete evidence and told to produce a patch, not a chat.
TAU_PROMPT="$(cat <<PROMPT
You are operating in scope "${SCOPE_NAME}" as an agentic coding fixer.
The tool-calling layer is FLAILING: model calls are failing, and the root cause
appears to be SSE stream handling for /v1/chat/completions.

Evidence gathered from a live probe is below. Treat it as ground truth.

$(cat "$REPORT")

Your task:
1. Read the evidence. Identify which models actually emit a usable OpenAI-style
   SSE stream (data: chunks + data: [DONE]).
2. Inspect the ${SCOPE_NAME} codebase for the code path that consumes
   /v1/chat/completions. Look for brittle assumptions: hard-coded model IDs,
   missing text/event-stream handling, missing [DONE] termination, failure to
   fall back when a model returns 200 but no SSE.
3. Produce a MINIMAL patch that makes ${SCOPE_NAME} dynamic:
   - keep the model catalog in memory at startup (from GET /v1/models),
   - select an SSE-capable model at runtime, and
   - add a guard/fallback for models whose SSE stream is absent or malformed.
4. Do not refactor broadly. One focused patch. If you need to see a file,
   read it. If you need to run a command to verify, do so.

When finished, respond with:
- The files changed.
- The exact diff (or a unified diff).
- A one-paragraph explanation of why this fixes the flailing.
PROMPT
)"

log "Invoking tau -p for agentic patch generation ..."
"$TAU_BIN" -p \
  --model "$TAU_MODEL" \
  --auto-approve \
  --cwd "$(pwd)" \
  "$TAU_PROMPT" | tee "$WORK_DIR/tau_patch.md"

log "Done. Patch proposal: $WORK_DIR/tau_patch.md"
log "Report: $REPORT"