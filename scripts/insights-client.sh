#!/usr/bin/env bash
# insights-client.sh — thin HTTP wrapper around the insights server.
#
# Subcommands:
#   list                            GET    /insights              -> JSON array
#   get <id>                        GET    /insights/<id>         -> single card
#   search [--scope S] [--priority P] <query> [cwd] -> JSON array
#   create <json-file|->            POST   /insights              -> created card
#   update <id> <json-file|->       PATCH  /insights/<id>         -> updated card
#   delete <id>                     DELETE /insights/<id>         -> {deleted: id}
#   stats [cwd]                     GET    /stats                 -> {total,new,session_relevant,...}
#   ping                            GET    /healthz               -> "ok" or non-zero exit
#   outbox-flush                    Flush any cards saved offline to the server
#
# Reads ${INSIGHTS_SERVER_URL}, ${INSIGHTS_AUTH_TOKEN}.
# Falls back to local cache (read-only) when offline. Offline create writes to outbox.

set -euo pipefail

SERVER_URL="${INSIGHTS_SERVER_URL:-http://localhost:7777}"
AUTH_TOKEN="${INSIGHTS_AUTH_TOKEN:-}"
CACHE_PATH="${INSIGHTS_CACHE_PATH:-$HOME/.claude/insights/cache.json}"
OUTBOX_DIR="${INSIGHTS_OUTBOX_DIR:-$HOME/.claude/insights/outbox}"

mkdir -p "$(dirname "$CACHE_PATH")" "$OUTBOX_DIR"

_curl() {
  local args=(-sS --fail --connect-timeout 2 --max-time 4)
  [[ -n "$AUTH_TOKEN" ]] && args+=(-H "Authorization: Bearer ${AUTH_TOKEN}")
  curl "${args[@]}" "$@"
}

_cache_read() {
  [[ -f "$CACHE_PATH" ]] || { echo "[]"; return; }
  cat "$CACHE_PATH"
}

_cache_write() {
  printf '%s' "$1" > "$CACHE_PATH"
}

cmd_list() {
  local resp
  if resp=$(_curl "${SERVER_URL}/insights" 2>/dev/null); then
    _cache_write "$resp"
    printf '%s' "$resp"
  else
    _cache_read
  fi
}

cmd_search() {
  local since="" until="" status="" scope="" priority=""
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --until) until="${2:-}"; shift 2 ;;
      --status=*) status="${1#--status=}"; shift ;;
      --status) status="${2:-}"; shift 2 ;;
      --scope=*) scope="${1#--scope=}"; shift ;;
      --scope) scope="${2:-}"; shift 2 ;;
      --priority=*) priority="${1#--priority=}"; shift ;;
      --priority) priority="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  local q="${1:-}"
  local cwd="${2:-}"
  [[ -z "$q" && -z "$cwd" ]] && { echo "[]"; return; }
  if [[ -n "$since" || -n "$until" || -n "$status" || -n "$scope" || -n "$priority" ]]; then
    local all
    all=$(cmd_list 2>/dev/null || _cache_read)
    INSIGHTS_QUERY="$q" INSIGHTS_SINCE="$since" INSIGHTS_UNTIL="$until" INSIGHTS_STATUS="$status" INSIGHTS_SCOPE="$scope" INSIGHTS_PRIORITY="$priority" python3 -c '
import json, os, sys
q = os.environ.get("INSIGHTS_QUERY", "").lower()
since = os.environ.get("INSIGHTS_SINCE", "")
until = os.environ.get("INSIGHTS_UNTIL", "")
status = os.environ.get("INSIGHTS_STATUS", "")
scope = os.environ.get("INSIGHTS_SCOPE", "")
priority = os.environ.get("INSIGHTS_PRIORITY", "")
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
out = []
tokens = [t for t in q.replace(",", " ").split() if t]
for c in data if isinstance(data, list) else []:
    if not isinstance(c, dict):
        continue
    hay = json.dumps(c, ensure_ascii=False).lower()
    ts = str(c.get("created_at") or c.get("updated_at") or c.get("captured_at") or "")
    if q and q not in hay and not all(t in hay for t in tokens):
        continue
    if status and str(c.get("status", "")) != status:
        continue
    if scope and str(c.get("scope", "")) != scope:
        continue
    if priority and str(c.get("priority", "")) != priority:
        continue
    if since and ts[:10] < since:
        continue
    if until and ts[:10] > until:
        continue
    out.append(c)
print(json.dumps(out, ensure_ascii=False))
' <<<"$all"
    return
  fi
  local args=(--get)
  [[ -n "$q"   ]] && args+=(--data-urlencode "q=${q}")
  [[ -n "$cwd" ]] && args+=(--data-urlencode "cwd=${cwd}")
  local resp
  if resp=$(_curl "${args[@]}" "${SERVER_URL}/insights/search" 2>/dev/null); then
    printf '%s' "$resp"
    return
  fi
  # offline fallback: naive grep over cache
  if [[ ! -f "$CACHE_PATH" ]]; then
    echo "[]"
    return
  fi
  INSIGHTS_QUERY="$q" INSIGHTS_CACHE="$CACHE_PATH" python3 -c '
import json, os, sys
q = os.environ.get("INSIGHTS_QUERY", "").lower()
cache = os.environ.get("INSIGHTS_CACHE", "")
try:
    with open(cache) as f:
        data = json.load(f)
except Exception:
    print("[]"); sys.exit(0)
hits = [c for c in data if isinstance(c, dict) and any(
    q in str(v).lower() for v in c.values() if isinstance(v, (str, list)))]
print(json.dumps(hits))
' 2>/dev/null || echo "[]"
}

cmd_create() {
  local src="${1:--}"
  local body
  if [[ "$src" == "-" ]]; then
    body=$(cat)
  else
    body=$(cat "$src")
  fi
  if _curl -X POST -H "Content-Type: application/json" \
           --data-binary "$body" \
           "${SERVER_URL}/insights"; then
    return 0
  fi
  # offline: queue to outbox
  local stamp
  stamp=$(date +%s%N 2>/dev/null || date +%s)
  local outfile="${OUTBOX_DIR}/${stamp}.json"
  printf '%s' "$body" > "$outfile"
  printf '{"queued":true,"outbox":"%s"}' "$outfile"
}

cmd_get() {
  local id="${1:-}"
  [[ -z "$id" ]] && { echo '{"error":"id_required"}'; return 2; }
  _curl "${SERVER_URL}/insights/${id}"
}

cmd_update() {
  local id="${1:-}"
  local src="${2:--}"
  [[ -z "$id" ]] && { echo '{"error":"id_required"}'; return 2; }
  local body
  if [[ "$src" == "-" ]]; then
    body=$(cat)
  else
    body=$(cat "$src")
  fi
  _curl -X PATCH -H "Content-Type: application/json" \
        --data-binary "$body" \
        "${SERVER_URL}/insights/${id}"
}

cmd_delete() {
  local id="${1:-}"
  [[ -z "$id" ]] && { echo '{"error":"id_required"}'; return 2; }
  _curl -X DELETE "${SERVER_URL}/insights/${id}"
}

cmd_outbox_flush() {
  local sent=0 failed=0
  shopt -s nullglob
  for f in "${OUTBOX_DIR}"/*.json; do
    if _curl -X POST -H "Content-Type: application/json" \
             --data-binary "@${f}" \
             "${SERVER_URL}/insights" >/dev/null 2>&1; then
      rm -f "$f"
      sent=$((sent + 1))
    else
      failed=$((failed + 1))
    fi
  done
  shopt -u nullglob
  printf '{"sent":%d,"failed":%d}' "$sent" "$failed"
}

cmd_stats() {
  local cwd="${1:-}"
  local resp
  if [[ -n "$cwd" ]]; then
    resp=$(_curl --get --data-urlencode "cwd=${cwd}" "${SERVER_URL}/stats" 2>/dev/null) || resp=""
  else
    resp=$(_curl "${SERVER_URL}/stats" 2>/dev/null) || resp=""
  fi
  if [[ -n "$resp" ]]; then
    printf '%s' "$resp"
  else
    # offline: derive from cache
    if [[ ! -f "$CACHE_PATH" ]]; then
      echo '{"total":0,"new":0,"session_relevant":0,"online":false}'
      return
    fi
    INSIGHTS_CACHE="$CACHE_PATH" python3 -c '
import json, os
cache = os.environ.get("INSIGHTS_CACHE", "")
try:
    with open(cache) as f:
        data = json.load(f)
except Exception:
    data = []
print(json.dumps({"total": len(data), "new": 0, "session_relevant": 0, "online": False}))
' 2>/dev/null || echo '{"total":0,"new":0,"session_relevant":0,"online":false}'
  fi
}

cmd_ping() {
  _curl "${SERVER_URL}/healthz" >/dev/null 2>&1
}

case "${1:-}" in
  list)         shift; cmd_list "$@" ;;
  get)          shift; cmd_get "$@" ;;
  search)       shift; cmd_search "$@" ;;
  create)       shift; cmd_create "$@" ;;
  update)       shift; cmd_update "$@" ;;
  delete)       shift; cmd_delete "$@" ;;
  stats)        shift; cmd_stats "$@" ;;
  ping)         shift; cmd_ping "$@" ;;
  outbox-flush) shift; cmd_outbox_flush "$@" ;;
  *)
    cat >&2 <<'USAGE'
usage: insights-client.sh <verb> [args]
  list                            list all insights
  get <id>                        fetch a single card
  search [--scope S] [--priority P] <q> [cwd]
                                  keyword + cwd-tag search
  create <file|->                 POST a new card (offline -> outbox)
  update <id> <file|->            PATCH an existing card
  delete <id>                     remove a card
  stats [cwd]                     totals + session-relevant count
  ping                            healthz probe
  outbox-flush                    push queued offline writes
USAGE
    exit 2
    ;;
esac
