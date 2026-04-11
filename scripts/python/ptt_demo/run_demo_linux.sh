#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

API_HOST="${API_HOST:-0.0.0.0}"
API_PORT="${API_PORT:-8090}"
ESL_HOST="${ESL_HOST:-127.0.0.1}"
ESL_PORT="${ESL_PORT:-8021}"
ESL_PASSWORD="${ESL_PASSWORD:-ClueCon}"
FS_DOMAIN="${FS_DOMAIN:-127.0.0.1}"
RECORDINGS_DIR="${RECORDINGS_DIR:-/usr/local/freeswitch/recordings}"
FS_BIN="${FS_BIN:-/usr/local/freeswitch/bin/freeswitch}"
AUTO_START_FS="${AUTO_START_FS:-1}"
SMOKE_TEST="${SMOKE_TEST:-1}"
KEEP_RUNNING="${KEEP_RUNNING:-1}"

usage() {
  cat <<'EOF'
Usage: run_demo_linux.sh [options]

Options:
  --api-host <host>         API bind host (default: 0.0.0.0)
  --api-port <port>         API port (default: 8090)
  --esl-host <host>         ESL host (default: 127.0.0.1)
  --esl-port <port>         ESL port (default: 8021)
  --esl-password <pwd>      ESL password (default: ClueCon)
  --fs-domain <domain>      FS domain used by room names
  --recordings-dir <path>   Recording directory path
  --fs-bin <path>           FreeSWITCH binary path
  --no-auto-start-fs        Do not auto-start FreeSWITCH when 8021 is down
  --no-smoke-test           Skip API smoke test
  --once                    Run smoke test then exit (stop API)
  -h, --help                Show this help

Env vars also supported: API_HOST API_PORT ESL_HOST ESL_PORT ESL_PASSWORD FS_DOMAIN RECORDINGS_DIR FS_BIN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-host) API_HOST="$2"; shift 2 ;;
    --api-port) API_PORT="$2"; shift 2 ;;
    --esl-host) ESL_HOST="$2"; shift 2 ;;
    --esl-port) ESL_PORT="$2"; shift 2 ;;
    --esl-password) ESL_PASSWORD="$2"; shift 2 ;;
    --fs-domain) FS_DOMAIN="$2"; shift 2 ;;
    --recordings-dir) RECORDINGS_DIR="$2"; shift 2 ;;
    --fs-bin) FS_BIN="$2"; shift 2 ;;
    --no-auto-start-fs) AUTO_START_FS=0; shift ;;
    --no-smoke-test) SMOKE_TEST=0; shift ;;
    --once) KEEP_RUNNING=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}

require_cmd python3
require_cmd curl

tcp_check() {
  local host="$1"
  local port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z "$host" "$port" >/dev/null 2>&1
    return $?
  fi
  (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
}

wait_port() {
  local host="$1"
  local port="$2"
  local timeout_s="$3"
  local i=0
  while (( i < timeout_s )); do
    if tcp_check "$host" "$port"; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

if ! tcp_check "$ESL_HOST" "$ESL_PORT"; then
  if [[ "$AUTO_START_FS" -eq 1 ]]; then
    if [[ ! -x "$FS_BIN" ]]; then
      echo "ERROR: ESL unreachable and FreeSWITCH binary not found/executable: $FS_BIN" >&2
      exit 1
    fi

    echo "ESL not reachable. Starting FreeSWITCH..."
    "$FS_BIN" -nonat >/dev/null 2>&1 || true

    if ! wait_port "$ESL_HOST" "$ESL_PORT" 25; then
      echo "ERROR: FreeSWITCH started but ESL $ESL_HOST:$ESL_PORT is still unreachable." >&2
      echo "Check event_socket config and firewall settings." >&2
      exit 1
    fi
  else
    echo "ERROR: ESL endpoint $ESL_HOST:$ESL_PORT is unreachable." >&2
    exit 1
  fi
fi

echo "ESL check passed: $ESL_HOST:$ESL_PORT"

echo "Preparing Python environment..."
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi

.venv/bin/python -m pip install --upgrade pip >/dev/null
.venv/bin/python -m pip install -r requirements.txt >/dev/null

echo "Generating bot audio..."
"$SCRIPT_DIR/generate_bot_audio_linux.sh"

export ESL_HOST ESL_PORT ESL_PASSWORD FS_DOMAIN RECORDINGS_DIR

API_URL="http://127.0.0.1:$API_PORT"

echo "Starting demo API on $API_HOST:$API_PORT ..."
.venv/bin/python -m uvicorn ptt_demo_service:app --host "$API_HOST" --port "$API_PORT" >/tmp/ptt-demo-api.log 2>&1 &
API_PID=$!

cleanup() {
  if kill -0 "$API_PID" >/dev/null 2>&1; then
    kill "$API_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! wait_port 127.0.0.1 "$API_PORT" 20; then
  echo "ERROR: API failed to start. Last logs:" >&2
  tail -n 80 /tmp/ptt-demo-api.log >&2 || true
  exit 1
fi

echo "API started: $API_URL"

if [[ "$SMOKE_TEST" -eq 1 ]]; then
  "$SCRIPT_DIR/api_smoke_test_linux.sh" "$API_URL"
fi

if [[ "$KEEP_RUNNING" -eq 1 ]]; then
  echo "Demo is running. Press Ctrl+C to stop."
  tail -f /tmp/ptt-demo-api.log
else
  echo "Run completed (--once)."
fi
