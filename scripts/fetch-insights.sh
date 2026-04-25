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

# Parallel-fetch all keyword queries — typical hooks complete in ~1 RTT.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

search_pids=()
i=0
for q in $keywords; do
  i=$((i + 1))
  ( bash "$CLIENT" search "$q" > "${tmpdir}/${i}.json" 2>/dev/null || echo "[]" > "${tmpdir}/${i}.json" ) &
  search_pids+=($!)
done
for pid in "${search_pids[@]}"; do wait "$pid"; done

# Merge + dedup by (id, title). Cap at 5.
hits_json=$(TMPDIR_FOR_HITS="$tmpdir" python3 -c '
import glob, json, os
out = []
seen = set()
for path in sorted(glob.glob(os.path.join(os.environ["TMPDIR_FOR_HITS"], "*.json"))):
    try:
        with open(path) as f:
            cards = json.load(f)
    except Exception:
        continue
    if not isinstance(cards, list):
        continue
    for c in cards:
        if not isinstance(c, dict):
            continue
        k = (c.get("id"), (c.get("title") or "").strip().lower())
        if k in seen:
            continue
        seen.add(k)
        out.append(c)
        if len(out) >= 5:
            break
    if len(out) >= 5:
        break
print(json.dumps(out))
')

count=$(printf '%s' "$hits_json" | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)))
except Exception: print(0)')

[[ "$count" -eq 0 ]] && exit 0

# Render as a concise context block.
printf '\n<insights-share>\n'
printf 'The following %s team insight(s) appear relevant to this prompt. Treat them as prior lessons learned by other Claude instances on this team. Do not repeat the mistakes they describe.\n\n' "$count"
printf '%s' "$hits_json" | python3 -c '
import json, sys, textwrap
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
for i, c in enumerate(data, 1):
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
'
printf '</insights-share>\n'
