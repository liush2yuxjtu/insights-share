#!/usr/bin/env bash
# fetch-insights.sh — UserPromptSubmit hook.
# Force-runs on every user prompt. Looks up relevant insights and injects them
# as additional context for the receiving Claude instance.
#
# Hook input (stdin, JSON): { "session_id": "...", "prompt": "...", ... }
# Hook output (stdout): plain-text additional context appended to the prompt.
# Exit 0: success. Non-zero suppressed by Claude Code (won't block the prompt).

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"

input=$(cat || true)
prompt=$(printf '%s' "$input" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("prompt",""))
except Exception: print("")' 2>/dev/null || true)

# Extract bag of meaningful keywords: >=4 chars, lowercase, stopword-filtered, dedup, top 5.
STOPWORDS="have that with this from should would could will into about your them \
they then there here what when where will because been being before after \
while both also just like more most some such than very want need make only \
even what which whose whom does done same many much each every other another \
than then though through these those over under above below between among \
without within across against during without around always never sometimes"

keywords=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9_-' '\n' \
  | awk -v stop="$STOPWORDS" 'BEGIN{
        n = split(stop, arr, /[[:space:]]+/)
        for (i = 1; i <= n; i++) sw[arr[i]] = 1
    }
    length($0) >= 4 && !($0 in sw) { print }' \
  | sort -u | head -n 5 | tr '\n' ' ')

[[ -z "${keywords// }" ]] && exit 0

# One list/cache read is faster and more stable than spawning one client per
# keyword, especially against the local stub where each search reloads JSON.
cards_json=$(bash "$CLIENT" list 2>/dev/null || echo "[]")

printf '%s' "$cards_json" | INSIGHTS_KEYWORDS="$keywords" python3 -c '
import json, os, sys, textwrap
keywords = [k for k in (os.environ.get("INSIGHTS_KEYWORDS") or "").split() if k]
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
if not isinstance(data, list) or not keywords:
    sys.exit(0)
out = []
seen = set()
for c in data:
    if not isinstance(c, dict):
        continue
    hay = json.dumps(c, ensure_ascii=False).lower()
    if not any(k in hay for k in keywords):
        continue
    key = (c.get("id"), (c.get("title") or "").strip().lower())
    if key in seen:
        continue
    seen.add(key)
    out.append(c)
    if len(out) >= 5:
        break
if not out:
    sys.exit(0)
print()
print("<insights-share>")
print(
    f"The following {len(out)} team insight(s) appear relevant to this prompt. "
    "Treat them as prior lessons learned by other Claude instances on this team. "
    "Do not repeat the mistakes they describe."
)
print()
for i, c in enumerate(out, 1):
    title  = c.get("title", "(untitled)")
    trap   = c.get("trap", "") or c.get("problem", "")
    fix    = c.get("fix", "")  or c.get("solution", "")
    tags   = ",".join(c.get("tags", []) or [])
    author = c.get("author", "unknown")
    print(f"[{i}] {title}  -  by {author}  [{tags}]")
    if trap:
        print(textwrap.fill(f"    trap: {trap}", width=100, subsequent_indent="          "))
    if fix:
        print(textwrap.fill(f"    fix:  {fix}",  width=100, subsequent_indent="          "))
    print()
print("</insights-share>")
'
