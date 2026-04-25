#!/usr/bin/env bash
# filter-haiku.sh — Layer 2 (haiku/claudefast single-pass) PII redactor +
# topic tag inferencer.
#
# Per design doc P5 Layer 2:
#   Input schema:  {turn_text: string, prior_redactions: span[]}
#   Output schema: {redact_spans: span[], confidence: 0-1, topic_tags: string[]}
# Single haiku call returns both privacy spans AND topic tags (cost-amortized).
#
# Timeout: 2s per turn → drop turn from upload (turn still seen by user).
# Confidence < 0.8 → drop turn from upload (same semantics).
#
# Usage:
#   cat redacted-text.txt | filter-haiku.sh
#   echo '{"turn_text": "...", "prior_redactions": [...]}' | filter-haiku.sh --json-in
#
# Output: JSON {redact_spans, confidence, topic_tags, dropped: bool, reason: ?}

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TIMEOUT_S="${INSIGHTS_HAIKU_TIMEOUT_S:-2}"
MIN_CONFIDENCE="${INSIGHTS_HAIKU_MIN_CONFIDENCE:-0.8}"
HAIKU_BIN="${INSIGHTS_HAIKU_BIN:-claudefast}"

mode="text-in"
case "${1:-}" in
  --json-in) mode="json-in" ;;
  --self-test)
    if ! command -v "$HAIKU_BIN" >/dev/null 2>&1; then
      echo "SKIP: $HAIKU_BIN not in PATH (offline self-test)"
      exit 0
    fi
    sample='Spent 30 minutes debugging a Vue 3 reactivity bug — turned out the prop was being mutated. Lesson: always use computed/ref instead of mutating props.'
    out=$(printf '%s' "$sample" | bash "$0" 2>/dev/null || echo '{}')
    echo "$out" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("FAIL: invalid JSON output"); sys.exit(1)
ok = isinstance(d, dict) and "topic_tags" in d and "confidence" in d
print("PASS" if ok else f"FAIL: missing keys in {d}")
'
    exit 0
    ;;
esac

# Read input
if [[ "$mode" == "json-in" ]]; then
  payload=$(cat)
  turn_text=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("turn_text",""))
except Exception: print("")')
else
  turn_text=$(cat)
fi

if [[ -z "${turn_text// }" ]]; then
  printf '{"redact_spans":[],"confidence":1.0,"topic_tags":[],"dropped":true,"reason":"empty"}\n'
  exit 0
fi

# Bail-out: if no haiku binary available, return empty pass-through but mark dropped.
if ! command -v "$HAIKU_BIN" >/dev/null 2>&1; then
  printf '{"redact_spans":[],"confidence":0.0,"topic_tags":[],"dropped":true,"reason":"no_haiku_binary"}\n'
  exit 0
fi

prompt="You are a PII filter and topic tagger. Output ONLY a single JSON object on one line.

Schema: {\"redact_spans\": [{\"start\":int,\"end\":int,\"reason\":str}], \"confidence\": float (0-1), \"topic_tags\": [str]}

Rules:
- redact_spans: byte-offset ranges in TURN_TEXT for any PII the regex pre-pass missed (rare custom tokens, customer names, internal acronyms with secret value, internal URLs, addresses).
- confidence: how sure you are (0.8 = high, <0.8 = uncertain → caller will drop turn).
- topic_tags: 1-5 short kebab-case tags routing this turn to similar future turns. Examples: vue-reactivity, gradle-cache-invalidation, kotlin-coroutine-leak, postgres-deadlock. Tags are RETRIEVAL keys, not solution authority.

TURN_TEXT:
---
$turn_text
---"

# Run haiku with timeout. Capture stdout only.
result=$(printf '%s' "$prompt" | timeout "${TIMEOUT_S}s" "$HAIKU_BIN" -p '' 2>/dev/null || echo "")

if [[ -z "$result" ]]; then
  printf '{"redact_spans":[],"confidence":0.0,"topic_tags":[],"dropped":true,"reason":"timeout_or_error"}\n'
  exit 0
fi

# Parse haiku output: extract first JSON object on the line. Drop if invalid.
parsed=$(printf '%s' "$result" | python3 -c '
import json, re, sys
text = sys.stdin.read()
# Find first {...} block
m = re.search(r"\{.*\}", text, re.DOTALL)
if not m:
    print("")
    sys.exit(0)
try:
    obj = json.loads(m.group(0))
except Exception:
    print("")
    sys.exit(0)
if not isinstance(obj, dict):
    print("")
    sys.exit(0)
obj.setdefault("redact_spans", [])
obj.setdefault("confidence", 0.0)
obj.setdefault("topic_tags", [])
obj["dropped"] = False
print(json.dumps(obj))
' 2>/dev/null || true)

if [[ -z "$parsed" ]]; then
  printf '{"redact_spans":[],"confidence":0.0,"topic_tags":[],"dropped":true,"reason":"unparseable"}\n'
  exit 0
fi

# Drop on low confidence
final=$(printf '%s' "$parsed" | INSIGHTS_MIN_CONF="$MIN_CONFIDENCE" python3 -c '
import json, os, sys
min_conf = float(os.environ["INSIGHTS_MIN_CONF"])
obj = json.loads(sys.stdin.read())
if float(obj.get("confidence", 0)) < min_conf:
    obj["dropped"] = True
    obj["reason"] = "low_confidence"
print(json.dumps(obj))
')

printf '%s\n' "$final"
