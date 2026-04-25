#!/usr/bin/env bash
# promote-insights.sh — promote a repeated cross-project tag cluster to team scope.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"

usage() {
  cat >&2 <<'USAGE'
usage: promote-insights.sh --tags tag1,tag2 [--scope team]
       promote-insights.sh --ids id1,id2 [--scope team]
USAGE
}

tags_csv=""
ids_csv=""
scope="team"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags) tags_csv="${2:-}"; shift 2 ;;
    --tags=*) tags_csv="${1#--tags=}"; shift ;;
    --ids) ids_csv="${2:-}"; shift 2 ;;
    --ids=*) ids_csv="${1#--ids=}"; shift ;;
    --level) scope="${2:-team}"; shift 2 ;;
    --level=*) scope="${1#--level=}"; shift ;;
    --scope) scope="${2:-team}"; shift 2 ;;
    --scope=*) scope="${1#--scope=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -n "$ids_csv" ]]; then
  result="[]"
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  IFS=',' read -r -a ids <<< "$ids_csv"
  printf '[' > "$tmp"
  first=1
  for id in "${ids[@]}"; do
    id="${id// /}"
    [[ -n "$id" ]] || continue
    patch=$(mktemp)
    printf '{"scope":"%s","status":"promoted","source_id":"%s"}' "$scope" "$id" > "$patch"
    updated=$(bash "$CLIENT" update "$id" "$patch")
    rm -f "$patch"
    [[ "$first" == "0" ]] && printf ',' >> "$tmp"
    printf '%s' "$updated" >> "$tmp"
    first=0
  done
  printf ']\n' >> "$tmp"
  cat "$tmp"
  exit 0
fi

[[ -n "$tags_csv" ]] || { usage; exit 2; }

all=$(bash "$CLIENT" list)
promotion=$(INSIGHTS_TAGS="$tags_csv" INSIGHTS_SCOPE="$scope" python3 -c '
import json, os, sys

priority_rank = {"critical": 4, "high": 3, "medium": 2, "low": 1}
required = [t.strip().lower() for t in os.environ["INSIGHTS_TAGS"].split(",") if t.strip()]
scope = os.environ.get("INSIGHTS_SCOPE", "team")
try:
    cards = json.load(sys.stdin)
except Exception:
    cards = []

matches = []
projects = []
authors = []
for card in cards if isinstance(cards, list) else []:
    if not isinstance(card, dict):
        continue
    card_tags = [str(t).lower() for t in card.get("tags", []) or []]
    if not all(tag in card_tags for tag in required):
        continue
    source = (
        card.get("project_slug")
        or card.get("repo_slug")
        or card.get("project")
        or card.get("cwd")
        or card.get("source_project")
        or "unknown"
    )
    matches.append(card)
    if source not in projects:
        projects.append(source)
    author = card.get("author")
    if author and author not in authors:
        authors.append(author)

if len(matches) < 2 or len(projects) < 2:
    print(json.dumps({
        "promoted": False,
        "reason": "threshold_not_met",
        "required_tags": required,
        "match_count": len(matches),
        "project_count": len(projects),
        "source_projects": projects,
    }))
    sys.exit(3)

ids = [str(c.get("id", "")) for c in matches if c.get("id")]
best_priority = ""
for card in matches:
    p = str(card.get("priority", "")).lower()
    if priority_rank.get(p, 0) > priority_rank.get(best_priority, 0):
        best_priority = p

tag_text = ",".join(required)
title = f"Team memory: {tag_text}"
fix_text = "Before related work, review source insight ids: " + ", ".join(ids) + "."
evidence_text = "promoted_from=" + ",".join(ids) + "; source_projects=" + ",".join(projects)
payload = {
    "title": title,
    "trap": f"Cross-project hotspot detected for tags [{tag_text}] across {len(projects)} projects.",
    "fix": fix_text,
    "evidence": evidence_text,
    "tags": ["team", "promoted"] + required,
    "scope": scope,
    "status": "promoted",
    "author": "insights-share@promote",
    "promoted_from": ids,
    "source_projects": projects,
    "source_authors": authors,
    "priority": best_priority or "medium",
}
print(json.dumps(payload, ensure_ascii=False))
' <<<"$all")

if echo "$promotion" | grep -q '"promoted": false'; then
  printf '%s\n' "$promotion"
  exit 3
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s' "$promotion" > "$tmp"
bash "$CLIENT" create "$tmp"
