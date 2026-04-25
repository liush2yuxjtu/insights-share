#!/usr/bin/env bash
# retrieve-local.sh — local-cache retrieval, hot-path ≤500ms p95.
#
# Per design doc:
#   Routing latency budget = UserPromptSubmit injection ≤500ms p95.
#   Hot path = local cache only (NO git fetch in hot path).
#   Retrieval = topic-tag exact match → fallback to embedding similarity.
#   Empty-state behavior: 0 lessons in cache → skip injection silently.
#
# Output: JSON array of top-3 lesson cards, each shaped like:
#   {id, captured_at, commit_id, topic_tags, kind, text, score}
#
# Usage:
#   retrieve-local.sh <repo-slug> <prompt-text>      # → JSON [{...}, ...]
#   retrieve-local.sh --self-test

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"
TOP_K="${INSIGHTS_RETRIEVAL_TOP_K:-3}"

if [[ "${1:-}" == "--self-test" ]]; then
  tmp=$(mktemp -d)
  slug="github.com__test__retr"
  fakedir="${INSIGHTS_ROOT}/${slug}"
  mkdir -p "$fakedir/.mirror"
  cat > "$fakedir/.mirror/lessons.jsonl" <<'EOF'
{"id":"l1","captured_at":1000,"commit_id":"abc","topic_tags":["vue-reactivity","frontend"],"kind":"raw","text":"Mutating props in Vue 3 leaks state."}
{"id":"l2","captured_at":2000,"commit_id":"def","topic_tags":["postgres","deadlock"],"kind":"raw","text":"Skipping FOR UPDATE deadlocked the order writer."}
{"id":"l3","captured_at":3000,"commit_id":"ghi","topic_tags":["gradle"],"kind":"raw","text":"Stale gradle cache breaks AAR resolution."}
EOF
  out=$(bash "$0" "$slug" "vue reactivity bug")
  rm -rf "$fakedir" "$tmp"
  echo "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
ok = isinstance(d, list) and len(d) >= 1 and any("vue" in t for t in d[0].get("topic_tags",[]))
print("PASS" if ok else f"FAIL: {d}")
'
  exit 0
fi

slug="${1:-}"; shift || true
prompt="${*:-}"

[[ -z "$slug" || -z "$prompt" ]] && { echo "[]"; exit 0; }

# Hot-path: read mirror lessons.jsonl + local lessons.jsonl, NO git fetch.
mirror_lessons="${INSIGHTS_ROOT}/${slug}/.mirror/lessons.jsonl"
local_lessons="${INSIGHTS_ROOT}/${slug}/lessons.jsonl"

PROMPT="$prompt" \
MIRROR="$mirror_lessons" \
LOCAL="$local_lessons" \
TOPK="$TOP_K" \
PLUGIN_ROOT="$PLUGIN_ROOT" \
python3 - <<'PYEOF'
import json
import os
import re
import subprocess
import sys

prompt = os.environ["PROMPT"].lower()
files = [os.environ["MIRROR"], os.environ["LOCAL"]]
top_k = int(os.environ["TOPK"])

lessons = []
seen = set()
for f in files:
    if not os.path.exists(f):
        continue
    try:
        for line in open(f):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            i = obj.get("id")
            if i in seen:
                continue
            seen.add(i)
            lessons.append(obj)
    except Exception:
        continue

if not lessons:
    print("[]")
    sys.exit(0)

# Tokenize prompt
prompt_tokens = set(re.findall(r"[a-z0-9]{4,}", prompt))

scored = []
for L in lessons:
    tags = [t.lower() for t in L.get("topic_tags", [])]
    text = (L.get("text", "") or "").lower()
    # Score = topic-tag exact-match (heavier) + bag-of-words overlap on text.
    tag_hits = 0
    for t in tags:
        for pt in prompt_tokens:
            if pt in t or t in pt:
                tag_hits += 1
    bag_overlap = len(prompt_tokens & set(re.findall(r"[a-z0-9]{4,}", text)))
    score = 3 * tag_hits + bag_overlap
    if score > 0:
        scored.append((score, L))

# If exact/keyword retrieval found nothing, try embedding fallback.
if not scored:
    embed = os.path.join(os.environ["PLUGIN_ROOT"], "scripts", "embed-fallback.py")
    if os.path.exists(embed):
        try:
            payload = json.dumps({"prompt": prompt, "lessons": lessons, "top_k": top_k})
            res = subprocess.run(
                ["python3", embed],
                input=payload, capture_output=True, text=True, timeout=2,
            )
            if res.returncode == 0:
                fallback = json.loads(res.stdout)
                if isinstance(fallback, list):
                    print(json.dumps(fallback))
                    sys.exit(0)
        except Exception:
            pass
    print("[]")
    sys.exit(0)

scored.sort(key=lambda x: -x[0])
out = []
for s, L in scored[:top_k]:
    L = dict(L)
    L["score"] = s
    out.append(L)
print(json.dumps(out))
PYEOF
