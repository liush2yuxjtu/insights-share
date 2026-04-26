#!/usr/bin/env bash
# add-insight.sh — /insight-add backing with Layer-1 PII and rate limiting.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"
RATE_PATH="${INSIGHTS_ADD_RATE_PATH:-$HOME/.claude/insights/add-rate.jsonl}"
RATE_LIMIT="${INSIGHTS_ADD_RATE_LIMIT:-10}"
RATE_WINDOW_S="${INSIGHTS_ADD_RATE_WINDOW_S:-60}"

src="${1:--}"
if [[ "$src" == "-" ]]; then
  body=$(cat)
else
  body=$(cat "$src")
fi

mkdir -p "$(dirname "$RATE_PATH")"
now=$(date +%s)
recent=$(NOW="$now" WINDOW="$RATE_WINDOW_S" RATE_PATH="$RATE_PATH" python3 - <<'PY'
import os, time
now = int(os.environ["NOW"])
window = int(os.environ["WINDOW"])
path = os.environ["RATE_PATH"]
kept = []
try:
    with open(path) as fh:
        for line in fh:
            try:
                ts = int(line.strip())
            except Exception:
                continue
            if now - ts < window:
                kept.append(ts)
except FileNotFoundError:
    pass
with open(path, "w") as fh:
    for ts in kept:
        fh.write(str(ts) + "\n")
print(len(kept))
PY
)

if [[ "$recent" -ge "$RATE_LIMIT" ]]; then
  printf '{"rate_limited":true,"limit":%d,"window_seconds":%d}\n' "$RATE_LIMIT" "$RATE_WINDOW_S"
  exit 29
fi

redacted=$(PLUGIN_ROOT="$PLUGIN_ROOT" python3 -c '
import importlib.util, json, os, re, sys

body = json.load(sys.stdin)
helper = os.path.join(os.environ["PLUGIN_ROOT"], "scripts", "_filter_pii.py")
spec = importlib.util.spec_from_file_location("_filter_pii", helper)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

tags = {str(t).lower() for t in body.get("tags", []) or []}
direct_feedback = bool(tags & {"direct-feedback", "feedback", "sales", "customer", "interview"})
name_rx = re.compile(r"\b[A-Z][a-z]{2,}\s+[A-Z][a-z]{2,}\b")
changed = False

def clean(value):
    global changed
    if isinstance(value, str):
        out, _ = mod.redact(value)
        if direct_feedback:
            out2 = name_rx.sub("[REDACTED:person_name]", out)
            out = out2
        if out != value:
            changed = True
        return out
    if isinstance(value, list):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    return value

out = clean(body)
if changed and isinstance(out, dict):
    out["pii_redacted"] = True
print(json.dumps(out, ensure_ascii=False))
' <<<"$body")

missing=$(INSIGHTS_BODY="$redacted" python3 - <<'PY'
import json
import os

body = json.loads(os.environ["INSIGHTS_BODY"])
required = ["title", "trap", "fix", "evidence"]
print(",".join(k for k in required if not body.get(k)))
PY
)
if [[ -n "$missing" ]]; then
  printf '{"error":"invalid_card","missing":"%s"}\n' "$missing"
  exit 2
fi

existing=$(bash "$CLIENT" list 2>/dev/null || echo "[]")
duplicate=$(INSIGHTS_BODY="$redacted" INSIGHTS_EXISTING="$existing" python3 - <<'PY'
import json
import os

body = json.loads(os.environ["INSIGHTS_BODY"])
title = str(body.get("title", "")).strip().casefold()
try:
    cards = json.loads(os.environ["INSIGHTS_EXISTING"])
except Exception:
    cards = []
for card in cards if isinstance(cards, list) else []:
    if not isinstance(card, dict):
        continue
    if str(card.get("title", "")).strip().casefold() == title:
        out = dict(card)
        out["duplicate"] = True
        print(json.dumps(out, ensure_ascii=False))
        break
PY
)
if [[ -n "$duplicate" ]]; then
  printf '%s\n' "$duplicate"
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s' "$redacted" > "$tmp"
resp=$(bash "$CLIENT" create "$tmp")
printf '%s\n' "$now" >> "$RATE_PATH"
printf '%s\n' "$resp"
