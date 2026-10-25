#!/usr/bin/env bash
# kappa anti-flail runtime — dynamic model discovery + loop guard + tool circuit breaker
# 由 tau -p 或直接 bash 驱动；不会在任何步骤依赖硬编码模型名。
set -euo pipefail

API_BASE="${FREEINFERENCE_API_BASE:-https://freeinference.org/v1}"
API_KEY="${FREEINFERENCE_API_KEY:?export FREEINFERENCE_API_KEY first}"
MAX_TURNS="${KAPPA_MAX_TURNS:-12}"
TOOL_BREAKER="${KAPPA_TOOL_BREAKER:-3}"          # 同一工具连续失败 N 次 -> 禁用该工具
LOOP_WINDOW="${KAPPA_LOOP_WINDOW:-3}"            # 相同工具+参数出现 N 次 -> 判定循环
STATE_DIR="/tmp/kappa_anti_flail_$$"
mkdir -p "$STATE_DIR"
trap 'rm -rf "$STATE_DIR"' EXIT

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die()  { log "FATAL: $*"; exit 1; }

# ---------- 1. 动态模型发现：/v1/models -> 内存数组 ----------
declare -a MODELS=()
declare -A MODEL_LATENCY_MS=()   # 内存中的延迟账本，供路由用

discover_models() {
  local raw
  raw=$(curl -sf -H "Authorization: Bearer $API_KEY" "$API_BASE/models") \
    || die "GET /models failed"
  mapfile -t MODELS < <(jq -r '.data[].id' <<<"$raw")
  [[ ${#MODELS[@]} -gt 0 ]] || die "model catalog empty"
  log "discovered ${#MODELS[@]} models: ${MODELS[*]}"
}

# ---------- 2. SSE 端点模糊探测（运行中执行，不阻塞主循环） ----------
SSE_ENDPOINT=""
fuzz_sse() {
  local base="$API_BASE" p
  for p in models models/stream models/sse chat/completions/stream; do
    local ct
    ct=$(curl -sfN -o /dev/null -w '%{content_type}' \
      -H "Authorization: Bearer $API_KEY" "$base/$p" 2>/dev/null || true)
    if [[ "$ct" == *"text/event-stream"* ]]; then
      SSE_ENDPOINT="$base/$p"
      log "SSE endpoint resolved: $SSE_ENDPOINT"
      return
    fi
  done
  log "no SSE endpoint found; falling back to buffered /chat/completions"
}

# ---------- 3. 模型延迟探测（用于路由，而非信任固定 fallback 链） ----------
probe_latency() {
  local model="$1" t0 t1 resp
  t0=$(date +%s%3N)
  resp=$(curl -sf -X POST "$API_BASE/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg m "$model" '{model:$m,messages:[{role:"user",content:"ping"}],max_tokens:1}')" 2>/dev/null || true)
  t1=$(date +%s%3N)
  if [[ -n "$resp" ]]; then
    MODEL_LATENCY_MS["$model"]=$((t1 - t0))
    log "probe $model: $((t1 - t0)) ms"
  else
    MODEL_LATENCY_MS["$model"]=999999
    log "probe $model: FAILED (marked hot)"
  fi
}

pick_model() {
  local best="" bestms=999999 m ms
  for m in "${!MODEL_LATENCY_MS[@]}"; do
    ms="${MODEL_LATENCY_MS[$m]}"
    if (( ms < bestms )); then bestms=$ms; best=$m; fi
  done
  [[ -n "$best" ]] || die "no live model to route to"
  echo "$best"
}

# ---------- 4. tool 执行 + 熔断 ----------
declare -A TOOL_FAILS=()

run_tool() {
  local name="$1" args="$2" out
  if (( ${TOOL_FAILS[$name]:-0} >= TOOL_BREAKER )); then
    log "tool '$name' tripped breaker (${TOOL_FAILS[$name]} consecutive fails) — refusing"
    return 1
  fi
  if out=$(bash -c "$args" 2>&1); then
    TOOL_FAILS[$name]=0
    printf '%s\n' "$out"
  else
    TOOL_FAILS[$name]=$(( ${TOOL_FAILS[$name]:-0} + 1 ))
    log "tool '$name' failed (${TOOL_FAILS[$name]}/$TOOL_BREAKER): $(printf '%s' "$out" | head -c 200)"
    printf 'ERROR: %s\n' "$out"
  fi
}

# ---------- 5. 循环指纹 ----------
loop_hash() { printf '%s|%s' "$1" "$2" | sha256sum | cut -c1-16; }
declare -a LOOP_FP=()
declare -A FP_COUNT=()

record_fp() {
  local fp="$1"
  FP_COUNT[$fp]=$(( ${FP_COUNT[$fp]:-0} + 1 ))
  LOOP_FP+=("$fp")
  (( ${FP_COUNT[$fp]} >= LOOP_WINDOW ))
}

# ---------- 6. 主代理循环 ----------
main() {
  discover_models
  fuzz_sse &          # 并行探测，不阻塞
  local i
  for i in "${!MODELS[@]}"; do
    probe_latency "${MODELS[$i]}" &   # 并行探测延迟
  done
  wait

  local model
  model=$(pick_model)
  log "routing to fastest model: $model"

  local messages='[{"role":"user","content":"You are an agent fixing a failing tau fallback chain. Use bash to inspect /tmp and propose one concrete fix. Reply with JSON: {\"tool\":\"bash\",\"args\":\"...\"} only."}]'
  local turn=0

  while (( turn < MAX_TURNS )); do
    turn=$((turn+1))
    log "--- turn $turn/$MAX_TURNS (model=$model) ---"

    local payload resp content tool args fp
    payload=$(jq -n --arg m "$model" --argjson msgs "$messages" \
      '{model:$m,messages:$msgs,max_tokens:300,temperature:0}')

    resp=$(curl -sf -X POST "$API_BASE/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" 2>/dev/null || true)

    if [[ -z "$resp" ]]; then
      log "model $model returned empty — evicting and re-routing"
      MODEL_LATENCY_MS["$model"]=999999
      model=$(pick_model)
      continue
    fi

    content=$(jq -r '.choices[0].message.content // ""' <<<"$resp")
    # 从内容里抠出 tool/args（兼容模型把 JSON 包在 prose 里的情况）
    tool=$(jq -Rr 'try (capture("\\\"tool\\\"\\s*:\\s*\\\"(?<t>[^\\\"]+)\\\"")?.t) catch ""' <<<"$content")
    args=$(jq -Rr 'try (capture("\\\"args\\\"\\s*:\\s*\\\"(?<a>.*?)\\\"")?.a) catch ""' <<<"$content")

    if [[ -z "$tool" || -z "$args" ]]; then
      log "no parsable tool call in turn $turn — injecting correction nudge"
      messages=$(jq -c --arg nudge 'Your last reply had no valid {"tool","args"}. Reply with valid JSON only.' \
        '. + [{role:"user",content:$nudge}]' <<<"$messages")
      continue
    fi

    fp=$(loop_hash "$tool" "$args")
    if record_fp "$fp"; then
      log "LOOP DETECTED on fp=$fp ($tool) — breaking cycle, switching model"
      messages=$(jq -c --arg nudge "Loop detected on tool=$tool. Choose a DIFFERENT approach or state BLOCKED." \
        '. + [{role:"user",content:$nudge}]' <<<"$messages")
      model=$(pick_model)
      continue
    fi

    log "tool=$tool args=$(printf '%s' "$args" | head -c 120)"
    local result
    result=$(run_tool "$tool" "$args" || true)
    messages=$(jq -c --arg r "$result" '. + [{role:"user",content:("TOOL RESULT:\n" + $r)}]' <<<"$messages")
  done

  log "exhausted $MAX_TURNS turns — writing final state to $STATE_DIR"
  printf '%s\n' "${LOOP_FP[@]}" > "$STATE_DIR/loop_fingerprints.txt"
  log "loop fingerprints: $(wc -l < "$STATE_DIR/loop_fingerprints.txt") recorded"
}

main