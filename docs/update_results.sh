#!/usr/bin/env bash
set -euo pipefail

# Update freshrss-status/results.json by appending a new run.
# Requirements: bash + curl + jq

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_PATH="$ROOT_DIR/results.json"

TARGET_URL="${1:-}"
if [[ -z "$TARGET_URL" ]]; then
  echo "Usage: $0 <target_url>" >&2
  exit 2
fi

NOW_ISO=$(date -Iseconds)
START_MS=$(date +%s%3N)

HTTP_CODE=""
ERR=""
# Example check: simple GET (customize to your actual FreshRSS endpoint + auth)
HTTP_CODE=$(curl -sS -o /tmp/freshrss_check_body.$$ -w "%{http_code}" --max-time 15 "$TARGET_URL" 2>/tmp/freshrss_check_err.$$ || true)
END_MS=$(date +%s%3N)
DURATION_MS=$((END_MS-START_MS))

if [[ -s /tmp/freshrss_check_err.$$ ]]; then
  ERR=$(tail -n 1 /tmp/freshrss_check_err.$$ | tr -d '\n' || true)
fi

STATUS="ok"
MSG="HTTP ${HTTP_CODE}"

if [[ "$HTTP_CODE" != "200" ]]; then
  STATUS="fail"
  MSG="HTTP ${HTTP_CODE}${ERR:+; ${ERR}}"
elif (( DURATION_MS > 1500 )); then
  STATUS="warn"
  MSG="HTTP 200; latency high (${DURATION_MS}ms)"
else
  MSG="HTTP 200; latency ok (${DURATION_MS}ms)"
fi

RUN=$(jq -n \
  --arg ts "$NOW_ISO" \
  --arg check "freshrss" \
  --arg target "$TARGET_URL" \
  --arg status "$STATUS" \
  --arg message "$MSG" \
  --argjson duration_ms "$DURATION_MS" \
  '{ts:$ts,check:$check,target:$target,status:$status,duration_ms:$duration_ms,message:$message}')

# init file if missing
if [[ ! -f "$JSON_PATH" ]]; then
  jq -n --arg now "$NOW_ISO" '{meta:{env:"prod",subtitle:"FreshRSS 巡检",updated_at:$now,overall_status:"unknown",build:""},runs:[]}' > "$JSON_PATH"
fi

TMP="$JSON_PATH.tmp"

jq --arg now "$NOW_ISO" --arg status "$STATUS" --arg build "$(hostname)-$(date +%Y%m%d)" \
  --argjson run "$RUN" \
  '(.meta.updated_at=$now)
   | (.meta.build=$build)
   | (.runs=[ $run ] + (.runs // []))
   | (.runs = (.runs | unique_by(.ts) | sort_by(.ts) | reverse))
   | (.runs = (.runs | .[0:200]))
   | (.meta.overall_status = ( .runs[0].status // $status ))
  ' "$JSON_PATH" > "$TMP"

mv "$TMP" "$JSON_PATH"

rm -f /tmp/freshrss_check_body.$$ /tmp/freshrss_check_err.$$

echo "Updated: $JSON_PATH"
