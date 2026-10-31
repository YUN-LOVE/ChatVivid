#!/usr/bin/env bash
# M0 smoke test: build must already exist.
# Usage: BIN=./build/dev/chatvvd PORT=18080 ./scripts/smoke.sh
set -euo pipefail

cd "$(dirname "$0")/.."

BIN="${BIN:-./build/dev/chatvvd}"
PORT="${PORT:-18080}"
DATA_DIR="$(mktemp -d)"
LOG="$DATA_DIR/server.log"
PID=""

cleanup() {
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

if [[ ! -x "$BIN" ]]; then
  echo "smoke: binary not found: $BIN" >&2
  exit 1
fi

CHATVV_PORT="$PORT" \
CHATVV_DATA_DIR="$DATA_DIR" \
CHATVV_INJECTIONS_DIR="$PWD/config/injections" \
  "$BIN" --config "$DATA_DIR/no-such-config.toml" >"$LOG" 2>&1 &
PID=$!

base="http://127.0.0.1:$PORT"
ready=0
i=0
while [[ "$i" -lt 60 ]]; do
  if curl -fsS "$base/healthz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
if [[ "$ready" != "1" ]]; then
  echo "smoke: server did not become healthy" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "smoke: health"
curl -fsS "$base/healthz" >/dev/null

echo "smoke: capabilities"
curl -fsS "$base/v1/capabilities" | python3 -c '
import json,sys
j=json.load(sys.stdin)
assert j["features"]["streaming"] is True, j
assert j["features"]["responses_api"] is True, j
'

echo "smoke: stream a turn"
curl -fsS -N -X POST "$base/v1/turns" \
  -H 'Content-Type: application/json' \
  -d '{"message":"smoke test"}' \
  --max-time 30 -o "$DATA_DIR/turn.sse"
grep -q '^event: response.created' "$DATA_DIR/turn.sse"
grep -q '^event: response.output_text.delta' "$DATA_DIR/turn.sse"
grep -q '^event: response.completed' "$DATA_DIR/turn.sse"

echo "smoke: history"
curl -fsS "$base/v1/messages?limit=50" -o "$DATA_DIR/messages.json"
python3 - "$DATA_DIR/messages.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
assert j["server_seq"] >= 2, j
assert len(j["data"]) >= 2, j
roles = [m["role"] for m in j["data"]]
assert "user" in roles and "assistant" in roles, roles
PY

echo "smoke: delta sync"
curl -fsS "$base/v1/messages/changes?since_seq=0" -o "$DATA_DIR/changes.json"
python3 - "$DATA_DIR/changes.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
assert j["server_seq"] >= 2, j
assert j["deleted"] == [], j
assert len(j["data"]) >= 2, j
PY

echo "smoke: context preview + injection"
curl -fsS -X POST "$base/v1/context/preview" \
  -H 'Content-Type: application/json' \
  -d '{"message":"preview","injections":[{"position":"before_latest","content":"note"}]}' \
  -o "$DATA_DIR/preview.json"
python3 - "$DATA_DIR/preview.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
assert j["manifest"]["position_counts"]["before_latest"] == 1, j["manifest"]
last = j["input"][-1]
assert last["role"] == "user"
assert len(last["content"]) == 2, last
assert "note" in last["content"][0]["text"]
PY

echo "smoke: PASS"
