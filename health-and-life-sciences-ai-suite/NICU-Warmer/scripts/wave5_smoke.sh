#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:5001}"
STATUS_TIMEOUT_SEC="${STATUS_TIMEOUT_SEC:-60}"
FRAME_TIMEOUT_SEC="${FRAME_TIMEOUT_SEC:-30}"
REQUIRE_FRAME="${REQUIRE_FRAME:-0}"

log() {
  echo "[wave5-smoke] $*"
}

fail() {
  echo "[wave5-smoke] ERROR: $*" >&2
  exit 1
}

log "Checking backend health at ${BASE_URL}/health"
health_payload="$(curl -fsS "${BASE_URL}/health")" || fail "Health endpoint unreachable"
echo "${health_payload}" | grep -q '"status":"healthy"' || fail "Backend not healthy: ${health_payload}"

log "Starting runtime"
start_payload="$(curl -fsS -X POST "${BASE_URL}/start")" || fail "Start request failed"
if ! echo "${start_payload}" | grep -Eq '"status":"starting"|"status":"running"|"message":"started"'; then
  fail "Unexpected start response: ${start_payload}"
fi

log "Polling /status until running (timeout ${STATUS_TIMEOUT_SEC}s)"
status_ok=0
for ((i=0; i<STATUS_TIMEOUT_SEC; i++)); do
  status_payload="$(curl -fsS "${BASE_URL}/status")" || true
  if echo "${status_payload}" | grep -Eq '"lifecycle":"running"|"runtime_status":"running"'; then
    status_ok=1
    break
  fi
  sleep 1
done
[[ "${status_ok}" -eq 1 ]] || fail "Runtime did not reach running state"

log "Checking SSE endpoint"
# We only need to verify that endpoint is reachable and returns an event stream payload.
# --max-time prevents hanging on a long-lived stream.
events_sample="$(curl -sS --max-time 3 "${BASE_URL}/events" | head -c 200 || true)"
if [[ -z "${events_sample}" ]]; then
  fail "No data sampled from /events"
fi

log "Polling frame availability (timeout ${FRAME_TIMEOUT_SEC}s)"
frame_ok=0
for ((i=0; i<FRAME_TIMEOUT_SEC; i++)); do
  frame_payload="$(curl -sS "${BASE_URL}/frame/latest?base64=1" || true)"
  if echo "${frame_payload}" | grep -q '"available":true'; then
    frame_ok=1
    break
  fi
  sleep 1
done
if [[ "${frame_ok}" -ne 1 ]]; then
  if [[ "${REQUIRE_FRAME}" == "1" ]]; then
    fail "Frame endpoint did not report available=true"
  fi
  log "WARNING: frame endpoint did not report available=true; continuing because REQUIRE_FRAME=0"
fi

log "Stopping runtime"
stop_payload="$(curl -fsS -X POST "${BASE_URL}/stop")" || fail "Stop request failed"
if ! echo "${stop_payload}" | grep -Eq '"status":"ready"|"status":"noop"'; then
  fail "Unexpected stop response: ${stop_payload}"
fi

log "Smoke completed successfully"
