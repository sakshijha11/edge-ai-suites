#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:5001}"
DURATION_SEC="${DURATION_SEC:-600}"
INTERVAL_SEC="${INTERVAL_SEC:-5}"
EVIDENCE_DIR="${EVIDENCE_DIR:-reference/soak_evidence}"

mkdir -p "${EVIDENCE_DIR}"
TS="$(date +%Y%m%d_%H%M%S)"
CSV_PATH="${EVIDENCE_DIR}/wave5_soak_${TS}.csv"
EVENTS_PATH="${EVIDENCE_DIR}/wave5_events_${TS}.log"

log() {
  echo "[wave5-soak] $*"
}

fail() {
  echo "[wave5-soak] ERROR: $*" >&2
  exit 1
}

log "Health check"
health_payload="$(curl -fsS "${BASE_URL}/health")" || fail "Health endpoint unreachable"
echo "${health_payload}" | grep -q '"status":"healthy"' || fail "Backend not healthy: ${health_payload}"

log "Start runtime"
curl -fsS -X POST "${BASE_URL}/start" > /dev/null || fail "Failed to start runtime"

log "Collecting soak samples for ${DURATION_SEC}s every ${INTERVAL_SEC}s"
echo "timestamp,lifecycle,runtime_status,fps,latency_ms,loop_count,frame_available" > "${CSV_PATH}"

end_epoch=$(( $(date +%s) + DURATION_SEC ))
while [[ "$(date +%s)" -lt "${end_epoch}" ]]; do
  status_payload="$(curl -sS "${BASE_URL}/status" || true)"
  frame_payload="$(curl -sS "${BASE_URL}/frame/latest?base64=1" || true)"

  readarray -t parsed < <(python3 - <<'PY' "$status_payload" "$frame_payload"
import json,sys,time
status_raw = sys.argv[1]
frame_raw = sys.argv[2]
now = int(time.time())
try:
    s = json.loads(status_raw)
except Exception:
    s = {}
try:
    f = json.loads(frame_raw)
except Exception:
    f = {}
print(now)
print(s.get("lifecycle", ""))
metrics = s.get("metrics", {}) if isinstance(s.get("metrics"), dict) else {}
print(metrics.get("runtime_status", ""))
print(metrics.get("fps", ""))
print(metrics.get("latency_ms", ""))
print(metrics.get("loop_count", ""))
print(str(f.get("available", False)).lower())
PY
)

  echo "${parsed[0]},${parsed[1]},${parsed[2]},${parsed[3]},${parsed[4]},${parsed[5]},${parsed[6]}" >> "${CSV_PATH}"

  # Sample SSE stream periodically to check reconnect/availability behavior.
  curl -sS --max-time 2 "${BASE_URL}/events" | head -c 500 >> "${EVENTS_PATH}" || true
  echo "" >> "${EVENTS_PATH}"

  sleep "${INTERVAL_SEC}"
done

log "Stop runtime"
curl -fsS -X POST "${BASE_URL}/stop" > /dev/null || fail "Failed to stop runtime"

log "Soak complete"
log "CSV evidence: ${CSV_PATH}"
log "SSE sample log: ${EVENTS_PATH}"
