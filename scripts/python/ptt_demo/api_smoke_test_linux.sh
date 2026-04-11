#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8090}"

curl_cmd() {
  curl -fsS "$@"
}

echo "Checking health..."
health_json="$(curl_cmd "$BASE_URL/health")"
echo "$health_json"

echo "Checking logs endpoint..."
logs_json="$(curl_cmd "$BASE_URL/api/logs")"
if command -v jq >/dev/null 2>&1; then
  echo "log_count=$(echo "$logs_json" | jq 'length')"
else
  echo "log_count=(install jq to show count)"
fi

echo "Triggering bot reply for site=1 channel=1..."
reply_json="$(curl_cmd -X POST "$BASE_URL/api/bot/reply" -H "Content-Type: application/json" -d '{"site":1,"channel":1,"question":"need safety reminder"}')"
echo "$reply_json"

echo "Smoke test finished."
