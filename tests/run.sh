#!/usr/bin/env bash
# tests/run.sh — auto-test driver. Boil-the-lake suite.
# Exits non-zero if any assertion fails.
#
# shellcheck disable=SC2015
# (`cond && ok ... || fail ...` is the test idiom here. ok/fail are pure
#  counter increments, so the false branch only runs when cond actually
#  failed — which is the intent.)

set -uo pipefail
ROOT="${1:-/Users/m1/projects/insights-share}"
PORT="${INSIGHTS_BIND_PORT:-7799}"

cd "$ROOT" || exit 1
export CLAUDE_PLUGIN_ROOT="$ROOT"
export INSIGHTS_BIND_PORT="$PORT"
export INSIGHTS_SERVER_URL="http://127.0.0.1:$PORT"
TMPROOT="$(mktemp -d)"
export INSIGHTS_CACHE_PATH="$TMPROOT/cache.json"
export INSIGHTS_OUTBOX_DIR="$TMPROOT/outbox"
export INSIGHTS_LESSON_LOG="$TMPROOT/last-trigger.log"
mkdir -p "$INSIGHTS_OUTBOX_DIR"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \e[32mok\e[0m  %s\n'   "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \e[31mFAIL\e[0m %s\n%s\n' "$1" "${2:-}"; }
sec()  { printf '\n=== %s ===\n' "$1"; }

bench_baseline_ms() {
  local samples=() s e sorted n p95_idx
  for _ in $(seq 1 10); do
    s=$(python3 -c 'import time;print(int(time.time()*1000))')
    bash -c ':' >/dev/null 2>&1
    e=$(python3 -c 'import time;print(int(time.time()*1000))')
    samples+=($((e-s)))
  done
  sorted=$(printf '%s\n' "${samples[@]}" | sort -n)
  n=${#samples[@]}
  p95_idx=$(( (n * 95 + 99) / 100 ))
  printf '%s\n' "$sorted" | sed -n "${p95_idx}p"
}

cleanup() {
  pkill -f "examples/server-stub.py" 2>/dev/null || true
  pkill -f '"127.0.0.1", 7898' 2>/dev/null || true
  rm -rf "$TMPROOT" ~/.claude/insights/server-stub.json
  return 0
}
trap cleanup EXIT

# Free the port if a previous run left a process behind.
pkill -f "examples/server-stub.py" 2>/dev/null || true
sleep 0.3

# ----------------------------------------------------------------------
sec "T6 stub: boot + healthz + endpoints"
python3 examples/server-stub.py >/tmp/insights-stub.log 2>&1 &
SRV_PID=$!
for _ in {1..30}; do
  curl -sS --max-time 1 "$INSIGHTS_SERVER_URL/healthz" 2>/dev/null | grep -q ok && break
  sleep 0.2
done
curl -sS --fail --max-time 1 "$INSIGHTS_SERVER_URL/healthz" >/dev/null \
  && ok "stub healthz" || fail "stub healthz"
[[ "$(curl -sS "$INSIGHTS_SERVER_URL/insights")" == "[]" ]] \
  && ok "stub /insights empty" || fail "stub /insights empty"
[[ "$(curl -sS "$INSIGHTS_SERVER_URL/stats" | python3 -c 'import sys,json; print(json.load(sys.stdin)["total"])')" == "0" ]] \
  && ok "stub /stats total=0" || fail "stub /stats total=0"
# bad JSON
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data 'NOT JSON' "$INSIGHTS_SERVER_URL/insights")
[[ "$code" == "400" ]] && ok "stub POST bad JSON -> 400" || fail "stub POST bad JSON" "got $code"
# missing title
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data '{"trap":"x"}' "$INSIGHTS_SERVER_URL/insights")
[[ "$code" == "400" ]] && ok "stub POST missing title -> 400" || fail "stub POST missing title" "got $code"
# 404
code=$(curl -sS -o /dev/null -w '%{http_code}' "$INSIGHTS_SERVER_URL/no-such-endpoint")
[[ "$code" == "404" ]] && ok "stub 404 unknown" || fail "stub 404 unknown" "got $code"

# ----------------------------------------------------------------------
sec "T5/T7 client online happy path"
bash scripts/insights-client.sh ping && ok "client ping ok" || fail "client ping"
created_id=$(bash scripts/insights-client.sh create examples/insight.example.json | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
[[ -n "$created_id" ]] && ok "client create -> id=$created_id" || fail "client create"
[[ "$(bash scripts/insights-client.sh list | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')" == "1" ]] \
  && ok "client list len=1 + cache populated" || fail "client list"
[[ -s "$INSIGHTS_CACHE_PATH" ]] && ok "cache file written" || fail "cache file written"

# search hits
hits=$(bash scripts/insights-client.sh search hook | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
[[ "$hits" -ge 1 ]] && ok "client search 'hook' returns >=1" || fail "client search 'hook'" "$hits"
# special-char query
hits=$(bash scripts/insights-client.sh search "a&b=c d?" | python3 -c 'import sys,json,os; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "ERR")
[[ "$hits" =~ ^[0-9]+$ ]] && ok "client search w/ special chars (no crash)" || fail "client search special chars" "$hits"
# empty query
empty=$(bash scripts/insights-client.sh search "")
[[ "$empty" == "[]" ]] && ok "client search empty -> []" || fail "client search empty" "$empty"

# ----------------------------------------------------------------------
sec "T5 add-insight PII redaction + rate limit"
pii_add=$(INSIGHTS_ADD_RATE_PATH="$TMPROOT/pii-rate.jsonl" bash scripts/add-insight.sh - <<'JSON'
{"title":"Competitor director John Smith shared Q3 pricing","trap":"John Smith said Q3 discounting may mislead planning","fix":"store direct feedback without names","evidence":"direct interview","tags":["pricing","direct-feedback"],"scope":"project","author":"alice"}
JSON
)
if echo "$pii_add" | grep -Fq '[REDACTED:person_name]' && ! echo "$pii_add" | grep -q 'John Smith'; then
  ok "add-insight redacts direct-feedback person name"
else
  fail "add-insight PII redaction" "$pii_add"
fi
pii_format=$(INSIGHTS_ADD_RATE_PATH="$TMPROOT/pii-format-rate.jsonl" bash scripts/add-insight.sh - <<'JSON'
{"title":"Auth log contains ops@example.com and 192.168.1.1","trap":"raw logs leak ops@example.com from 192.168.1.1","fix":"redact exact PII markers before storing","evidence":"ops@example.com via 192.168.1.1","tags":["auth"],"scope":"project","author":"alice"}
JSON
)
if echo "$pii_format" | grep -Fq '[REDACTED:email]' \
  && echo "$pii_format" | grep -Fq '[REDACTED:ip_address]' \
  && ! echo "$pii_format" | grep -q 'ops@example.com' \
  && ! echo "$pii_format" | grep -q '192.168.1.1'; then
  ok "add-insight emits exact email/ip redaction markers"
else
  fail "add-insight exact PII markers" "$pii_format"
fi
invalid_add=$(printf '%s' '{"title":"invalid missing fields","trap":"missing fix/evidence","tags":["test"],"scope":"project","author":"alice"}' \
  | INSIGHTS_ADD_RATE_PATH="$TMPROOT/invalid-rate.jsonl" bash scripts/add-insight.sh - 2>/dev/null || true)
echo "$invalid_add" | grep -q '"error":"invalid_card"' \
  && ok "add-insight rejects missing required fields" \
  || fail "add-insight invalid input" "$invalid_add"
dup_title="duplicate title $$"
first_dup=$(printf '{"title":"%s","trap":"t","fix":"f","evidence":"e","tags":["dup"],"scope":"project","author":"alice"}' "$dup_title" \
  | INSIGHTS_ADD_RATE_PATH="$TMPROOT/dup-rate.jsonl" bash scripts/add-insight.sh -)
second_dup=$(printf '{"title":"%s","trap":"new trap","fix":"new fix","evidence":"new evidence","tags":["dup"],"scope":"project","author":"alice"}' "$dup_title" \
  | INSIGHTS_ADD_RATE_PATH="$TMPROOT/dup-rate.jsonl" bash scripts/add-insight.sh -)
first_dup_id=$(printf '%s' "$first_dup" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
second_dup_id=$(printf '%s' "$second_dup" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
[[ -n "$first_dup_id" && "$first_dup_id" == "$second_dup_id" && "$second_dup" == *'"duplicate": true'* ]] \
  && ok "add-insight returns existing card for duplicate title" \
  || fail "add-insight duplicate detection" "$second_dup"

rate_dir="$TMPROOT/rate-limit"
mkdir -p "$rate_dir"
rate_limited="{}"
for i in 1 2 3 4; do
  body=$(printf '{"title":"rate limit %s","trap":"t","fix":"f","evidence":"e","tags":["rate"],"scope":"project","author":"rl"}' "$i")
  rate_limited=$(printf '%s' "$body" | INSIGHTS_ADD_RATE_LIMIT=3 INSIGHTS_ADD_RATE_WINDOW_S=60 INSIGHTS_ADD_RATE_PATH="$rate_dir/add-rate.jsonl" bash scripts/add-insight.sh - 2>/dev/null || true)
done
echo "$rate_limited" | grep -q '"rate_limited":true' \
  && ok "add-insight enforces local rate limit" \
  || fail "add-insight rate limit missing" "$rate_limited"

# ----------------------------------------------------------------------
sec "T4 hook synthetic input — UserPromptSubmit"
out=$(echo '{"prompt":"how should I write a SessionStart hook safely"}' | bash scripts/fetch-insights.sh)
[[ "$out" == *"<insights-share>"* && "$out" == *"hook"* ]] \
  && ok "fetch-insights injects relevant card" || fail "fetch-insights injection" "$out"

out_empty=$(echo '{"prompt":""}' | bash scripts/fetch-insights.sh)
[[ -z "$out_empty" ]] && ok "fetch-insights empty prompt -> no output" || fail "fetch-insights empty" "$out_empty"

out_short=$(echo '{"prompt":"a is b"}' | bash scripts/fetch-insights.sh)
[[ -z "$out_short" ]] && ok "fetch-insights short tokens -> no output" || fail "fetch-insights short tokens" "$out_short"

out_nojson=$(echo 'not json' | bash scripts/fetch-insights.sh)
[[ -z "$out_nojson" ]] && ok "fetch-insights bad input -> no crash" || fail "fetch-insights bad input" "$out_nojson"

# stale-prompt with totally unrelated keywords
out_unrel=$(echo '{"prompt":"recipe banana smoothie kitchen blender"}' | bash scripts/fetch-insights.sh)
[[ -z "$out_unrel" ]] && ok "fetch-insights unrelated -> no output" || fail "fetch-insights unrelated" "$out_unrel"

# ----------------------------------------------------------------------
sec "T4 hook synthetic input — SessionStart (CLAUDE.md append)"
TMP=$(mktemp -d)
echo "# Project XYZ" > "$TMP/CLAUDE.md"
echo "{\"cwd\":\"$TMP\"}" | bash scripts/append-claude-md.sh
echo "{\"cwd\":\"$TMP\"}" | bash scripts/append-claude-md.sh   # idempotency
mc=$(grep -c 'insights-share@v0.1' "$TMP/CLAUDE.md")
[[ "$mc" == "1" ]] && ok "append-claude-md idempotent (marker count=1)" || fail "append-claude-md idempotent" "marker=$mc"
[[ "$(head -1 "$TMP/CLAUDE.md")" == "# Project XYZ" ]] && ok "append-claude-md preserves prior content" || fail "append-claude-md preserves" "$(head -1 "$TMP/CLAUDE.md")"

# missing CLAUDE.md -> no-op
TMP2=$(mktemp -d)
echo "{\"cwd\":\"$TMP2\"}" | bash scripts/append-claude-md.sh
[[ ! -e "$TMP2/CLAUDE.md" ]] && ok "append-claude-md skips missing CLAUDE.md" || fail "append-claude-md skips missing"

# read-only CLAUDE.md -> exit 0 (no crash, just won't append)
TMP3=$(mktemp -d)
echo "# locked" > "$TMP3/CLAUDE.md"
chmod 0444 "$TMP3/CLAUDE.md"
if echo "{\"cwd\":\"$TMP3\"}" | bash scripts/append-claude-md.sh 2>/dev/null; then
  if grep -q 'insights-share@v0.1' "$TMP3/CLAUDE.md"; then
    fail "append-claude-md should not modify read-only file" ""
  else
    ok "append-claude-md leaves read-only file alone (gracefully)"
  fi
else
  ok "append-claude-md exits non-zero on read-only (acceptable)"
fi
chmod 0644 "$TMP3/CLAUDE.md"

rm -rf "$TMP" "$TMP2" "$TMP3"

# ----------------------------------------------------------------------
sec "T7 statusline ONLINE"
out=$(bash scripts/statusline.sh < /dev/null)
[[ "$out" =~ 💡\ [0-9]+ && "$out" == *"⏺"* ]] && ok "statusline online: '$out'" || fail "statusline online" "$out"
out=$(INSIGHTS_STATUSLINE_MODE=lite bash scripts/statusline.sh < /dev/null)
[[ "$out" =~ ^💡[0-9]+$ ]] && ok "statusline lite: '$out'" || fail "statusline lite" "$out"
out=$(INSIGHTS_STATUSLINE_MODE=ultra bash scripts/statusline.sh < /dev/null)
[[ "$out" == *"INSIGHTS"* && "$out" == *"srv ok"* ]] && ok "statusline ultra: '$out'" || fail "statusline ultra" "$out"

# malformed cwd in stdin shouldn't crash
out=$(echo 'not json' | bash scripts/statusline.sh)
[[ -n "$out" ]] && ok "statusline tolerates non-JSON stdin: '$out'" || fail "statusline non-JSON" "$out"

# ----------------------------------------------------------------------
sec "T7 OFFLINE — kill stub, exercise fallback"
kill -9 "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
sleep 0.3

ping_rc=0; bash scripts/insights-client.sh ping || ping_rc=$?
[[ "$ping_rc" -ne 0 ]] && ok "client ping fails offline (rc=$ping_rc)" || fail "client ping should fail offline"

stats=$(bash scripts/insights-client.sh stats)
echo "$stats" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["online"] is False; assert d["total"]>=0' \
  && ok "client stats offline ok: $stats" || fail "client stats offline" "$stats"

hits=$(bash scripts/insights-client.sh search hook | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "ERR")
[[ "$hits" =~ ^[0-9]+$ ]] && [[ "$hits" -ge 1 ]] && ok "client search offline cache hit: $hits" || fail "client search offline" "$hits"

out=$(bash scripts/statusline.sh < /dev/null)
[[ "$out" == *"○"* ]] && ok "statusline offline indicator '○': '$out'" || fail "statusline offline indicator" "$out"

out=$(INSIGHTS_STATUSLINE_MODE=ultra bash scripts/statusline.sh < /dev/null)
[[ "$out" == *"offline"* ]] && ok "statusline ultra offline label: '$out'" || fail "statusline ultra offline" "$out"

# fetch-insights offline still injects from cache
out=$(echo '{"prompt":"sessionstart hook"}' | bash scripts/fetch-insights.sh)
[[ "$out" == *"<insights-share>"* ]] && ok "fetch-insights offline injects from cache" || fail "fetch-insights offline" "$out"

# ----------------------------------------------------------------------
sec "T5 corrupted cache"
echo "garbage{[" > "$INSIGHTS_CACHE_PATH"
hits=$(bash scripts/insights-client.sh search hook 2>/dev/null || true)
[[ "$hits" == "[]" || -z "$hits" ]] && ok "search tolerates corrupt cache: '$hits'" || fail "search corrupt cache" "$hits"
stats=$(bash scripts/insights-client.sh stats)
echo "$stats" | python3 -c 'import sys,json; json.load(sys.stdin)' \
  && ok "stats tolerates corrupt cache: $stats" || fail "stats corrupt cache" "$stats"

# ----------------------------------------------------------------------
sec "T5 concurrent fetch-insights (no cache corruption)"
# repopulate cache first
python3 examples/server-stub.py >/tmp/insights-stub.log 2>&1 &
SRV_PID=$!
for _ in {1..30}; do
  curl -sS --max-time 1 "$INSIGHTS_SERVER_URL/healthz" 2>/dev/null | grep -q ok && break
  sleep 0.2
done
bash scripts/insights-client.sh create examples/insight.example.json >/dev/null
bash scripts/insights-client.sh list >/dev/null

# Hammer 5 parallel hooks
hook_pids=()
for i in 1 2 3 4 5; do
  ( echo "{\"prompt\":\"sessionstart hook iteration $i\"}" | bash scripts/fetch-insights.sh > "/tmp/fhook.$i.out" ) &
  hook_pids+=($!)
done
for pid in "${hook_pids[@]}"; do wait "$pid"; done
fail_concurrent=0
for i in 1 2 3 4 5; do
  if ! grep -q '<insights-share>' "/tmp/fhook.$i.out"; then
    fail_concurrent=1
    echo "  iter $i missing tag: $(cat /tmp/fhook.$i.out | head -3)"
  fi
done
[[ "$fail_concurrent" == "0" ]] && ok "5 parallel hooks all injected" || fail "concurrent hooks"
# cache still parseable
python3 -c "import json; json.load(open('$INSIGHTS_CACHE_PATH'))" \
  && ok "cache survives concurrent access" || fail "cache corrupt after concurrent"
rm -f /tmp/fhook.*.out

# ======================================================================
# BOIL-THE-LAKE: extended suite
# ======================================================================

# ----------------------------------------------------------------------
sec "BTL-1 stub CRUD: GET /<id>, PATCH, DELETE"
created=$(bash scripts/insights-client.sh create examples/insight.example.json)
new_id=$(printf '%s' "$created" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
[[ -n "$new_id" ]] && ok "create returns id=$new_id" || fail "create no id"

got=$(bash scripts/insights-client.sh get "$new_id")
[[ "$(printf '%s' "$got" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')" == "$new_id" ]] \
  && ok "GET /insights/<id> roundtrip" || fail "GET roundtrip" "$got"

# 404 for unknown id
unknown_code=$(curl -sS -o /dev/null -w '%{http_code}' "$INSIGHTS_SERVER_URL/insights/ins_does_not_exist")
[[ "$unknown_code" == "404" ]] && ok "GET unknown id -> 404" || fail "GET unknown 404" "$unknown_code"

# PATCH
patched=$(bash scripts/insights-client.sh update "$new_id" - <<<'{"title":"PATCHED title"}')
[[ "$(printf '%s' "$patched" | python3 -c 'import sys,json; print(json.load(sys.stdin)["title"])')" == "PATCHED title" ]] \
  && ok "PATCH title applied" || fail "PATCH title" "$patched"

# PATCH must not change id
[[ "$(printf '%s' "$patched" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')" == "$new_id" ]] \
  && ok "PATCH preserves id" || fail "PATCH id changed"

# Concurrent different-field edits must merge through partial PATCHes.
status_out="/tmp/insights-edit-status.$$"
tags_out="/tmp/insights-edit-tags.$$"
bash scripts/edit-insight.sh --id "$new_id" --field status --value archived > "$status_out" 2>&1 &
status_pid=$!
bash scripts/edit-insight.sh --id "$new_id" --field tags --value '["archived","crud"]' > "$tags_out" 2>&1 &
tags_pid=$!
edit_ok=1
wait "$status_pid" || edit_ok=0
wait "$tags_pid" || edit_ok=0
[[ "$edit_ok" == "1" ]] \
  && ok "concurrent edit commands both exited" \
  || fail "concurrent edit command failed" "$(cat "$status_out" "$tags_out" 2>/dev/null)"
edited=$(bash scripts/insights-client.sh get "$new_id")
merge_ok=$(printf '%s' "$edited" | python3 -c '
import json, sys
d = json.load(sys.stdin)
tags = set(d.get("tags") or [])
print("OK" if d.get("status") == "archived" and {"archived", "crud"} <= tags else json.dumps(d))
' 2>/dev/null || echo ERR)
[[ "$merge_ok" == "OK" ]] \
  && ok "concurrent different-field edits merged on one insight" \
  || fail "concurrent edit merge" "$merge_ok"
forbidden=$(bash scripts/edit-insight.sh --id "$new_id" --actor bob --field status --value archived 2>/dev/null || true)
author_edit=$(bash scripts/edit-insight.sh --id "$new_id" --field author --value bob 2>/dev/null || true)
if echo "$forbidden" | grep -q '"error":"forbidden"' && echo "$author_edit" | grep -q '"error":"immutable_field"'; then
  ok "edit-insight rejects non-author actor and author rewrites"
else
  fail "edit-insight permission boundary" "forbidden=$forbidden author_edit=$author_edit"
fi
rm -f "$status_out" "$tags_out"

# PATCH bad json -> 400
bad_patch=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH \
    -H 'Content-Type: application/json' --data 'NOT JSON' \
    "$INSIGHTS_SERVER_URL/insights/$new_id")
[[ "$bad_patch" == "400" ]] && ok "PATCH bad JSON -> 400" || fail "PATCH bad JSON" "$bad_patch"

# PATCH unknown id -> 404
miss_patch=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH \
    -H 'Content-Type: application/json' --data '{"x":1}' \
    "$INSIGHTS_SERVER_URL/insights/ins_missing")
[[ "$miss_patch" == "404" ]] && ok "PATCH unknown id -> 404" || fail "PATCH unknown 404" "$miss_patch"

# DELETE
del=$(bash scripts/delete-insight.sh --id "$new_id")
[[ "$(printf '%s' "$del" | python3 -c 'import sys,json; print(json.load(sys.stdin)["deleted"])')" == "$new_id" ]] \
  && ok "DELETE returns deleted id" || fail "DELETE id" "$del"
deleted_get=$(curl -sS -o /dev/null -w '%{http_code}' "$INSIGHTS_SERVER_URL/insights/$new_id")
[[ "$deleted_get" == "404" ]] && ok "GET deleted insight -> 404" || fail "GET deleted 404" "$deleted_get"
deleted_search=$(bash scripts/insights-client.sh search "$new_id")
echo "$deleted_search" | grep -q "$new_id" \
  && fail "deleted search" "$deleted_search" \
  || ok "deleted insight no longer appears in search"

# DELETE again -> 404
miss_del=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$INSIGHTS_SERVER_URL/insights/$new_id")
[[ "$miss_del" == "404" ]] && ok "DELETE already-gone -> 404" || fail "DELETE 404" "$miss_del"

# ----------------------------------------------------------------------
sec "BTL-2 search with cwd filter"
# create one card tagged auth, one tagged migration
bash scripts/insights-client.sh create - >/dev/null <<'JSON'
{"title":"auth token typo","trap":"x","fix":"y","evidence":"e","tags":["auth"],"scope":"project","author":"t"}
JSON
bash scripts/insights-client.sh create - >/dev/null <<'JSON'
{"title":"migration order matters","trap":"x","fix":"y","evidence":"e","tags":["migration"],"scope":"project","author":"t"}
JSON

n_auth=$(bash scripts/insights-client.sh search "" "/repo/auth/middleware" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
n_mig=$(bash scripts/insights-client.sh search "" "/repo/migrations" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
[[ "$n_auth" -ge 1 ]] && ok "cwd /auth surfaces 'auth' card ($n_auth)" || fail "cwd auth" "$n_auth"
[[ "$n_mig" -ge 1 ]] && ok "cwd /migrations surfaces 'migration' card ($n_mig)" || fail "cwd migration" "$n_mig"

# stats with cwd
sr=$(bash scripts/insights-client.sh stats "/repo/auth/middleware" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["session_relevant"])')
[[ "$sr" -ge 1 ]] && ok "stats?cwd= session_relevant=$sr" || fail "stats session_relevant" "$sr"

# ----------------------------------------------------------------------
sec "BTL-2b cross-project promotion + lineage"
front_id=$(bash scripts/insights-client.sh create - <<'JSON' | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])'
{"title":"RSC hydration boundary","trap":"RSC without a clear hydration boundary leaks client state","fix":"Keep architecture/rsc hydration boundaries explicit","evidence":"front terminal story","tags":["architecture","rsc"],"scope":"project","project_slug":"brain-frontend","priority":"high","author":"frank"}
JSON
)
back_id=$(bash scripts/insights-client.sh create - <<'JSON' | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])'
{"title":"RSC streaming gateway reuse","trap":"Gateway streaming can copy RSC assumptions blindly","fix":"Review RSC streaming constraints before API gateway reuse","evidence":"back terminal story","tags":["architecture","rsc"],"scope":"project","project_slug":"brain-backend","priority":"medium","author":"frank"}
JSON
)
[[ -n "$front_id" && -n "$back_id" ]] && ok "two cross-project source insights created" || fail "source insight ids" "$front_id / $back_id"

multi_hits=$(bash scripts/insights-client.sh search "architecture rsc" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
[[ "$multi_hits" -ge 2 ]] && ok "multi-token search finds architecture+rsc sources ($multi_hits)" || fail "multi-token search" "$multi_hits"

promoted=$(bash scripts/promote-insights.sh --tags architecture,rsc --scope team)
promoted_id=$(printf '%s' "$promoted" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
[[ -n "$promoted_id" ]] && ok "promote creates team insight id=$promoted_id" || fail "promote missing id" "$promoted"

PROMOTED_JSON="$promoted" python3 - "$front_id" "$back_id" <<'PY' \
  && ok "promoted card keeps team scope, priority, sources, and provenance" \
  || fail "promoted lineage fields" "$promoted"
import json, os, sys
card = json.loads(os.environ["PROMOTED_JSON"])
ids = {sys.argv[1], sys.argv[2]}
assert card.get("scope") == "team"
assert card.get("status") == "promoted"
assert card.get("priority") == "high"
assert {"brain-frontend", "brain-backend"} <= set(card.get("source_projects", []))
assert ids <= set(card.get("promoted_from", []))
PY

team_hits=$(bash scripts/insights-client.sh search "team architecture")
echo "$team_hits" | grep -q "$promoted_id" \
  && ok "team search finds promoted memory" \
  || fail "team search missed promoted memory" "$team_hits"
team_scope_hits=$(bash scripts/insights-client.sh search --scope team "team architecture")
scope_ok=$(printf '%s' "$team_scope_hits" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print("OK" if data and all(c.get("scope") == "team" for c in data) else "BAD")
' 2>/dev/null || echo BAD)
[[ "$team_scope_hits" == *"$promoted_id"* && "$scope_ok" == "OK" ]] \
  && ok "team scope search filters promoted memory" \
  || fail "team scope search" "$team_scope_hits"
priority_hits=$(bash scripts/insights-client.sh search --priority high "architecture rsc")
priority_ok=$(PRIORITY_HITS="$priority_hits" FRONT_ID="$front_id" BACK_ID="$back_id" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["PRIORITY_HITS"])
ids = {c.get("id") for c in data}
print("OK" if os.environ["FRONT_ID"] in ids and os.environ["BACK_ID"] not in ids else "BAD")
PY
)
[[ "$priority_ok" == "OK" ]] \
  && ok "priority search filters high-priority insights" \
  || fail "priority search" "$priority_hits"

log_json=$(bash scripts/insight-log.sh --id "$promoted_id" --json)
LOG_JSON="$log_json" python3 - "$front_id" "$back_id" <<'PY' \
  && ok "insight-log returns source projects and promoted_from" \
  || fail "insight-log lineage" "$log_json"
import json, os, sys
card = json.loads(os.environ["LOG_JSON"])
ids = {sys.argv[1], sys.argv[2]}
assert {"brain-frontend", "brain-backend"} <= set(card.get("source_projects", []))
assert ids <= set(card.get("promoted_from", []))
PY

# ----------------------------------------------------------------------
sec "BTL-3 perf budget — fetch-insights < 2s"
perf_baseline_ms=$(bench_baseline_ms)
perf_baseline_s=$(python3 -c "print(${perf_baseline_ms:-0}/1000)")
t_start=$(python3 -c 'import time; print(time.time())')
echo '{"prompt":"how should I write a SessionStart hook safely with auth and migration"}' \
  | bash scripts/fetch-insights.sh >/dev/null
t_end=$(python3 -c 'import time; print(time.time())')
elapsed=$(python3 -c "print(f'{${t_end}-${t_start}:.2f}')")
net_elapsed=$(python3 -c "print(f'{max(0, ${t_end}-${t_start}-${perf_baseline_s}):.2f}')")
under_budget=$(python3 -c "print(int(max(0, ${t_end}-${t_start}-${perf_baseline_s}) < 2.0))")
[[ "$under_budget" == "1" ]] && ok "fetch-insights ran in ${elapsed}s (${net_elapsed}s calibrated, <2s budget)" || fail "fetch-insights too slow" "${elapsed}s baseline=${perf_baseline_s}s net=${net_elapsed}s"

# ----------------------------------------------------------------------
sec "BTL-4 stress — large cache (200 cards) search remains fast"
python3 - >/dev/null <<PY
import json, urllib.request
url = "$INSIGHTS_SERVER_URL/insights"
for i in range(200):
    body = json.dumps({"title":f"stress card {i}","trap":f"trap{i}","fix":"f",
                       "evidence":"e","tags":["stress","perf"],
                       "scope":"project","author":"stress"}).encode()
    req = urllib.request.Request(url, data=body,
        headers={"Content-Type":"application/json"}, method="POST")
    urllib.request.urlopen(req).read()
PY
total=$(bash scripts/insights-client.sh stats | python3 -c 'import sys,json; print(json.load(sys.stdin)["total"])')
[[ "$total" -ge 200 ]] && ok "stress: server holds $total cards" || fail "stress count" "$total"

t0=$(python3 -c 'import time; print(time.time())')
hits=$(bash scripts/insights-client.sh search "stress" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
t1=$(python3 -c 'import time; print(time.time())')
search_elapsed=$(python3 -c "print(${t1}-${t0})")
search_net=$(python3 -c "print(max(0, ${search_elapsed}-${perf_baseline_s}))")
fast=$(python3 -c "print(int(${search_net} < 1.0))")
[[ "$fast" == "1" ]] && [[ "$hits" -ge 25 || "$hits" -ge 1 ]] \
  && ok "search across $total cards returned $hits in $(python3 -c "print(f'{${search_elapsed}:.2f}')")s ($(python3 -c "print(f'{${search_net}:.2f}')")s calibrated)" \
  || fail "search slow" "elapsed=${search_elapsed}s baseline=${perf_baseline_s}s net=${search_net}s, hits=$hits"

# ----------------------------------------------------------------------
sec "BTL-5 control characters / weird prompts"
out=$(printf '{"prompt":"hook \\u0000\\u0007\\u001b[31m hook auth"}' | bash scripts/fetch-insights.sh)
[[ "$out" == *"<insights-share>"* ]] && ok "fetch-insights tolerates control chars" || fail "control chars" "$out"

# Very long prompt
long_prompt=$(python3 -c 'print("hook auth migration "*500)')
out=$(python3 -c "import json; print(json.dumps({'prompt': '$long_prompt'}))" | bash scripts/fetch-insights.sh)
[[ "$out" == *"<insights-share>"* ]] && ok "fetch-insights handles 9KB prompt" || fail "long prompt" ""

# Unicode prompt (Chinese keywords)
out=$(echo '{"prompt":"如何安全地写 SessionStart hook 处理 auth 和 migration"}' | bash scripts/fetch-insights.sh)
[[ "$out" == *"<insights-share>"* ]] && ok "fetch-insights handles unicode + ascii kws" || fail "unicode prompt" "$out"

# ----------------------------------------------------------------------
sec "BTL-6 outbox queue when offline"
# kill stub temporarily
kill -9 "$SRV_PID" 2>/dev/null || true
sleep 0.3

resp=$(bash scripts/insights-client.sh create - <<<'{"title":"queued offline","trap":"t","fix":"f","evidence":"e","tags":["offline"],"scope":"project","author":"o"}')
[[ "$(printf '%s' "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("queued",False))')" == "True" ]] \
  && ok "offline create queues to outbox" || fail "offline queue" "$resp"

queued=$(find "$INSIGHTS_OUTBOX_DIR" -name '*.json' | wc -l | tr -d ' ')
[[ "$queued" -ge 1 ]] && ok "outbox has $queued queued file(s)" || fail "outbox empty" "$queued"

# Restart stub
python3 examples/server-stub.py >/tmp/insights-stub.log 2>&1 &
SRV_PID=$!
for _ in {1..30}; do
  curl -sS --max-time 1 "$INSIGHTS_SERVER_URL/healthz" 2>/dev/null | grep -q ok && break
  sleep 0.2
done

# Flush outbox
flush=$(bash scripts/insights-client.sh outbox-flush)
sent=$(printf '%s' "$flush" | python3 -c 'import sys,json; print(json.load(sys.stdin)["sent"])')
[[ "$sent" -ge 1 ]] && ok "outbox-flush sent $sent" || fail "outbox flush" "$flush"

remaining=$(find "$INSIGHTS_OUTBOX_DIR" -name '*.json' | wc -l | tr -d ' ')
[[ "$remaining" == "0" ]] && ok "outbox empty after flush" || fail "outbox not drained" "$remaining"

# ----------------------------------------------------------------------
sec "BTL-7 Stop hook — capture-lesson"
# transcript with trap-shaped phrase -> hook should fire
trans=$(mktemp)
cat > "$trans" <<'EOF'
ok so root cause was that the auth middleware uses < instead of <=
which let tokens expire one second too late. fixed it. lesson learned.
EOF
hook_in=$(printf '{"session_id":"sess-1","transcript_path":"%s","stop_hook_active":false}' "$trans")
out=$(echo "$hook_in" | bash scripts/capture-lesson.sh)
[[ "$out" == *"<insights-share>"* ]] && ok "Stop hook fires on lesson-shaped transcript" || fail "stop hook didn't fire" "$out"

# Same session again within 60s -> should NOT re-fire (debounce)
out2=$(echo "$hook_in" | bash scripts/capture-lesson.sh)
[[ -z "$out2" ]] && ok "Stop hook debounces same-session within 60s" || fail "stop hook debounce" "$out2"

# Boring transcript -> no fire
trans2=$(mktemp)
echo "looked fine, all tests passed, no surprises." > "$trans2"
hook_in2=$(printf '{"session_id":"sess-2","transcript_path":"%s","stop_hook_active":false}' "$trans2")
out3=$(echo "$hook_in2" | bash scripts/capture-lesson.sh)
[[ -z "$out3" ]] && ok "Stop hook silent on boring transcript" || fail "stop hook over-fires" "$out3"

# Missing transcript path -> exit 0, no output, no crash
out4=$(echo '{"session_id":"sess-3"}' | bash scripts/capture-lesson.sh)
[[ -z "$out4" ]] && ok "Stop hook tolerates missing transcript_path" || fail "stop hook missing path" "$out4"

rm -f "$trans" "$trans2"

# ----------------------------------------------------------------------
sec "BTL-8 server returns malformed body / 5xx — client must not crash"
# Spin up a one-shot misbehaving "server" on port 7898
python3 - <<'PY' >/tmp/bad-srv.log 2>&1 &
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/healthz"):
            self.send_response(500); self.end_headers(); return
        if self.path.startswith("/stats"):
            self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
            self.wfile.write(b"NOT JSON"); return
        if self.path.startswith("/insights"):
            self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
            self.wfile.write(b"<html>hijack</html>"); return
        self.send_response(404); self.end_headers()
    def log_message(self,*a,**kw): pass
HTTPServer(("127.0.0.1", 7898), H).serve_forever()
PY
BAD_PID=$!
sleep 0.5

INSIGHTS_SERVER_URL=http://127.0.0.1:7898 bash scripts/insights-client.sh ping >/dev/null 2>&1
rc=$?
[[ "$rc" -ne 0 ]] && ok "client ping detects 5xx as offline (rc=$rc)" || fail "ping should fail on 5xx"

stats_bad=$(INSIGHTS_SERVER_URL=http://127.0.0.1:7898 bash scripts/insights-client.sh stats)
echo "$stats_bad" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert "online" in d' \
  && ok "client stats survives malformed body: $stats_bad" || fail "stats malformed body" "$stats_bad"

INSIGHTS_SERVER_URL=http://127.0.0.1:7898 bash scripts/insights-client.sh search hook >/dev/null 2>&1 \
  && ok "client search survives malformed body (offline fallback)" \
  || fail "client search crashed on malformed body"

kill -9 "$BAD_PID" 2>/dev/null || true
sleep 0.3

# ----------------------------------------------------------------------
sec "BTL-9 statusline session-relevant changes with cwd"
# Move into auth-shaped path
out_auth=$(echo "{\"cwd\":\"/some/repo/auth/middleware\"}" \
  | bash scripts/statusline.sh)
out_unrelated=$(echo "{\"cwd\":\"/totally/unrelated/photos\"}" \
  | bash scripts/statusline.sh)
echo "  auth-cwd:        $out_auth"
echo "  unrelated-cwd:   $out_unrelated"
[[ "$out_auth" == *"🎯"* ]] && ok "statusline shows 🎯 marker per cwd" || fail "statusline 🎯 marker" "$out_auth"

# ----------------------------------------------------------------------
sec "BTL-10 client usage (unknown verb -> exit 2 with help)"
help_out=$(bash scripts/insights-client.sh wibble 2>&1 || true)
[[ "$help_out" == *"usage:"* ]] && ok "client unknown verb prints usage" || fail "no usage message"

# ----------------------------------------------------------------------
sec "BTL-11 frontmatter still parses for all SKILL.md after polish"
fm_ok=1
for f in skills/*/SKILL.md; do
  python3 -c "
import re, sys, pathlib
text = pathlib.Path('$f').read_text()
m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
assert m, 'no frontmatter in $f'
fm = m.group(1)
for k in ('name','description','argument-hint','allowed-tools'):
    assert k+':' in fm, f'missing $f: '+k
" 2>/dev/null || fm_ok=0
done
[[ "$fm_ok" == "1" ]] && ok "all SKILL.md frontmatter still valid" || fail "frontmatter regressed"

# ----------------------------------------------------------------------
sec "BTL-12 hooks.json schema (3 events)"
events=$(python3 -c "import json; print(','.join(sorted(json.load(open('hooks/hooks.json'))['hooks'].keys())))")
[[ "$events" == "SessionStart,Stop,UserPromptSubmit" ]] \
  && ok "hooks.json has all 3 events: $events" || fail "hooks.json events" "$events"

# ----------------------------------------------------------------------
sec "BTL-13 marketplace.json reachable through symlink"
mkt=/Users/m1/.claude/local-marketplaces/insights-share-marketplace
plg=$(python3 -c "import json; m=json.load(open('$mkt/.claude-plugin/marketplace.json')); print(m['plugins'][0]['source'])")
[[ -f "$mkt/$plg/.claude-plugin/plugin.json" ]] \
  && ok "marketplace plugin source reachable: $mkt/$plg" || fail "marketplace source missing" "$plg"

# Final: known_marketplaces registered
reg=$(python3 -c 'import json; d=json.load(open("/Users/m1/.claude/plugins/known_marketplaces.json")); print("insights-share-marketplace" in d)')
[[ "$reg" == "True" ]] && ok "registered in known_marketplaces.json" || fail "not registered"

# ----------------------------------------------------------------------
sec "B1 canonical-remote: HTTPS == SSH"
canon_https=$(echo "https://github.com/Foo/Bar.git" | bash scripts/canonical-remote.sh --from-url)
canon_ssh=$(echo "git@github.com:Foo/Bar.git"     | bash scripts/canonical-remote.sh --from-url)
[[ "$canon_https" == "$canon_ssh" && "$canon_https" == "github.com/foo/bar" ]] \
  && ok "canonical HTTPS=SSH normalised: $canon_https" \
  || fail "canonical mismatch" "https=$canon_https ssh=$canon_ssh"

# ----------------------------------------------------------------------
sec "B2 Layer 1 PII filter — adversarial leaks=0"
gate0_out=$(bash tests/gate0/run-gate0.sh --strict 2>&1 || true)
verdict=$(printf '%s' "$gate0_out" | python3 -c 'import json,sys,re
m = re.search(r"\{.*\}", sys.stdin.read(), re.S)
print(json.loads(m.group(0))["verdict"] if m else "ERR")' 2>/dev/null || echo ERR)
[[ "$verdict" == "PASS" ]] && ok "Gate-0 verdict PASS" || fail "Gate-0 verdict" "$verdict"

# ----------------------------------------------------------------------
sec "B3 Layer 2 haiku filter — schema valid (offline-tolerant)"
bash scripts/filter-haiku.sh --self-test >/dev/null 2>&1 \
  && ok "haiku filter self-test ok" \
  || fail "haiku filter self-test"

# ----------------------------------------------------------------------
sec "B4 PAT auth lifecycle (set/get/has/forget)"
slug_test="github.com__test__sample"
echo "ghp_pat_test_value_for_unit_check" | bash scripts/pat-auth.sh set "$slug_test" >/dev/null
bash scripts/pat-auth.sh has "$slug_test" && ok "PAT has after set" || fail "PAT has after set"
mode=$(stat -f '%Sp' "$HOME/.gstack/insights-auth/${slug_test}.token" 2>/dev/null \
       || stat -c '%A' "$HOME/.gstack/insights-auth/${slug_test}.token" 2>/dev/null)
[[ "$mode" == "-rw-------" ]] && ok "PAT chmod 600" || fail "PAT chmod" "$mode"
bash scripts/pat-auth.sh forget "$slug_test" >/dev/null
bash scripts/pat-auth.sh has "$slug_test" || ok "PAT cleared after forget"

# ----------------------------------------------------------------------
sec "B5 retrieve-local self-test"
bash scripts/retrieve-local.sh --self-test 2>&1 | grep -q PASS \
  && ok "retrieve-local self-test PASS" \
  || fail "retrieve-local self-test"

# ----------------------------------------------------------------------
sec "B6 inject-insights hot path ≤500ms p95 (20 iter)"
slug_pl="github.com__bench__insights-share"
mkdir -p "$HOME/.gstack/insights/${slug_pl}/.mirror"
cat > "$HOME/.gstack/insights/${slug_pl}/.mirror/lessons.jsonl" <<EOF2
{"id":"l1","captured_at":1000,"commit_id":"abc","topic_tags":["vue-reactivity"],"kind":"raw","text":"Mutating Vue 3 props leaks reactive state."}
{"id":"l2","captured_at":2000,"commit_id":"def","topic_tags":["postgres"],"kind":"raw","text":"FOR UPDATE deadlocked the order writer."}
{"id":"l3","captured_at":3000,"commit_id":"ghi","topic_tags":["gradle"],"kind":"raw","text":"Stale gradle cache breaks AAR resolution."}
EOF2
# Inject a fake remote via env so canonical_slug resolves to slug_pl.
benchdir=$(mktemp -d)
( cd "$benchdir" && git init -q && git remote add origin "git@github.com:bench/insights-share.git" )
# Stabilize the micro-benchmark after the preceding server/process tests.
sleep 1
for _ in 1 2 3; do
  echo '{"prompt":"vue reactivity bug help","cwd":"'$benchdir'","session_id":"warm"}' \
      | bash scripts/inject-insights.sh >/dev/null 2>&1
done
samples=()
for i in $(seq 1 20); do
  s=$(python3 -c 'import time;print(int(time.time()*1000))')
  echo '{"prompt":"vue reactivity bug help","cwd":"'$benchdir'","session_id":"l-'$i'"}' \
      | bash scripts/inject-insights.sh >/dev/null 2>&1
  e=$(python3 -c 'import time;print(int(time.time()*1000))')
  samples+=($((e-s)))
done
sorted_samples=$(printf '%s\n' "${samples[@]}" | sort -n)
n=${#samples[@]}
p95_idx=$(( (n * 95 + 99) / 100 ))
p95=$(printf '%s\n' "$sorted_samples" | sed -n "${p95_idx}p")
p95_net=$(python3 -c "print(max(0, int(${p95:-0}) - int(${perf_baseline_ms:-0})))")
[[ "${p95_net:-0}" -le 500 ]] \
  && ok "inject-insights p95=${p95}ms (${p95_net}ms calibrated) ≤ 500ms" \
  || fail "inject-insights p95 too slow" "${p95}ms baseline=${perf_baseline_ms}ms net=${p95_net}ms (samples: ${samples[*]})"
rm -rf "$HOME/.gstack/insights/${slug_pl}" "$benchdir"

# ----------------------------------------------------------------------
sec "B7 capture-async writes buffer + spawns watchdog"
asyncdir=$(mktemp -d)
( cd "$asyncdir" && git init -q && git remote add origin "git@github.com:bench/async.git" )
echo '{"session_id":"sB7","transcript_path":"/tmp/fake","cwd":"'$asyncdir'"}' \
  | bash scripts/capture-async.sh
slug_b7="github.com__bench__async"
[[ -f "$HOME/.gstack/insights/${slug_b7}/.buffer/sB7.jsonl" ]] \
  && ok "capture-async wrote buffer file" \
  || fail "buffer not written"
[[ -f "$HOME/.gstack/insights/${slug_b7}/.buffer/.watchdog-sB7.pid" ]] \
  && ok "watchdog pid file created" \
  || fail "watchdog not spawned"
# Cleanup
for pid in $(pgrep -f "finalize-buffer.sh ${slug_b7} sB7"); do kill "$pid" 2>/dev/null || true; done
rm -rf "$HOME/.gstack/insights/${slug_b7}" "$asyncdir"

# ----------------------------------------------------------------------
sec "B8 rate-lesson appends to ratings.jsonl"
ratedir=$(mktemp -d)
( cd "$ratedir" && git init -q && git remote add origin "git@github.com:bench/rate.git" )
slug_rate="github.com__bench__rate"
( cd "$ratedir" && bash "$ROOT/scripts/rate-lesson.sh" lesson-bench-1 good "smoke test" >/dev/null )
[[ -f "$HOME/.gstack/insights/${slug_rate}/ratings.jsonl" ]] \
  && ok "ratings.jsonl created" \
  || fail "ratings.jsonl missing"
last=$(tail -1 "$HOME/.gstack/insights/${slug_rate}/ratings.jsonl" 2>/dev/null \
       | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["verdict"])')
[[ "$last" == "good" ]] && ok "rating verdict round-trip" || fail "rating verdict" "$last"
rm -rf "$HOME/.gstack/insights/${slug_rate}" "$ratedir"

# ----------------------------------------------------------------------
sec "B9 sync-mirror status / ensure (offline-tolerant)"
status=$(bash scripts/sync-mirror.sh status github.com__nonexistent__test 2>/dev/null)
[[ "$status" == *'"clone":false'* ]] && ok "sync-mirror status reports false" || fail "sync-mirror status" "$status"
ensure=$(bash scripts/sync-mirror.sh ensure github.com__nonexistent__test 2>/dev/null)
echo "$ensure" | grep -q 'mirror_not_found' && ok "ensure logs mirror_not_found warning" \
  || fail "ensure missing warning" "$ensure"

# ----------------------------------------------------------------------
sec "B10 buffer-recover idempotent on empty dir"
out=$(bash scripts/buffer-recover.sh github.com__missing__buf 2>&1)
echo "$out" | grep -q '"recovered":0' && ok "buffer-recover handles missing dir" \
  || fail "buffer-recover" "$out"

# ----------------------------------------------------------------------
sec "B11 flush-buffer reports finalized count"
flushdir=$(mktemp -d)
( cd "$flushdir" && git init -q && git remote add origin "git@github.com:bench/flush.git" )
out=$(cd "$flushdir" && bash "$ROOT/scripts/flush-buffer.sh" 2>&1)
echo "$out" | grep -q '"finalized"' && ok "flush-buffer JSON includes finalized" \
  || fail "flush-buffer output" "$out"
rm -rf "$flushdir"

# ----------------------------------------------------------------------
sec "B12 embed-fallback degrades gracefully without sentence-transformers"
fb=$(printf '%s' '{"prompt":"vue","lessons":[{"id":"x","topic_tags":["vue"],"text":"vue 3 reactivity"}],"top_k":1}' \
     | python3 scripts/embed-fallback.py 2>/dev/null)
echo "$fb" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert isinstance(d,list) and d and "score" in d[0]' 2>/dev/null \
  && ok "embed-fallback returns scored list" \
  || fail "embed-fallback failed" "$fb"

# ----------------------------------------------------------------------
sec "B13 hooks.json wired to B-architecture entries"
ups=$(python3 -c "import json; print(json.load(open('hooks/hooks.json'))['hooks']['UserPromptSubmit'][0]['hooks'][0]['command'])")
[[ "$ups" == *"inject-insights.sh"* ]] && ok "UserPromptSubmit → inject-insights.sh" || fail "UserPromptSubmit cmd" "$ups"
stop=$(python3 -c "import json; print(json.load(open('hooks/hooks.json'))['hooks']['Stop'][0]['hooks'][0]['command'])")
[[ "$stop" == *"capture-async.sh"* ]] && ok "Stop → capture-async.sh" || fail "Stop cmd" "$stop"

# ----------------------------------------------------------------------
sec "B14 SKILL.md frontmatter for insight-rate / insight-flush / insight-promote / insight-log / insight-edit / insight-delete"
for s in insight-rate insight-flush insight-promote insight-log insight-edit insight-delete; do
  python3 -c "
import re, sys, pathlib
text = pathlib.Path('skills/$s/SKILL.md').read_text()
m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
assert m, 'no frontmatter $s'
fm = m.group(1)
for k in ('name','description','argument-hint','allowed-tools'):
    assert k+':' in fm, 'missing $s: '+k
" 2>/dev/null && ok "$s SKILL.md frontmatter ok" || fail "$s frontmatter"
done

# ----------------------------------------------------------------------
echo
printf '\n=== TOTAL: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" == "0" ]]
