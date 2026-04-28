#!/bin/bash
# backfill-topic-slug.sh — One-time backfill of topic_slug for existing index.json
#
# Usage:
#   scripts/backfill-topic-slug.sh           # dry-run, prints distribution
#   scripts/backfill-topic-slug.sh --apply   # writes back (with timestamped backup)
#
# Idempotent: existing topic_slug values are preserved.

set -e

TEAM_DIR="${HOME}/.claude-team"
INDEX="${TEAM_DIR}/insights/index.json"
APPLY=0

if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

if [[ ! -f "${INDEX}" ]]; then
  echo "[backfill] no index at ${INDEX}" >&2
  exit 1
fi

JQ_FILTER='
  .insights |= map(
    . as $e
    | (($e.name // "") + " " + ($e.when_to_use // "") + " " + ($e.description // "")) as $hay
    | . + {topic_slug: (
        if   ($e.topic_slug // null) != null                          then $e.topic_slug
        elif ($hay | test("jsonl|JSONL"; "i"))                        then "jsonl-ingestion"
        elif ($hay | test("rsync|bidirectional sync"; "i"))           then "rsync-sync"
        elif ($hay | test("haiku.*digest|digest.*haiku|nightly digest"; "i")) then "haiku-digest"
        elif ($hay | test("claudefast"; "i"))                         then "claudefast-runtime"
        elif ($hay | test("async|asyncio|event loop"; "i"))           then "async-python"
        elif ($hay | test("git\\s+(pull|push|merge|fetch|rebase)|submodule"; "i")) then "git-workflow"
        elif ($hay | test("TDD|coverage|pytest|jest|unittest"; "i"))  then "testing"
        elif ($hay | test("secret|credential|api[- ]?key|leak"; "i")) then "security"
        elif ($hay | test("subagent|sub-agent|spawn.*agent"; "i"))    then "agent-orchestration"
        elif ($hay | test("hook|UserPromptSubmit|SessionStart|PostToolUse"; "i")) then "claude-code-hooks"
        elif ($hay | test("\\bMCP\\b|context7"; "i"))                 then "mcp-tools"
        elif ($hay | test("plugin|skill"; "i"))                       then "claude-code-plugin"
        elif ($hay | test("rule|CLAUDE\\.md|AGENTS\\.md|memory|trap"; "i")) then "rules-memory"
        else "uncategorized"
        end
      )}
  )
'

NEW=$(jq "${JQ_FILTER}" "${INDEX}")

echo "[backfill] topic_slug distribution:"
echo "${NEW}" | jq -r '
  .insights
  | group_by(.topic_slug)
  | map({slug: .[0].topic_slug, count: length})
  | sort_by(-.count)
  | .[]
  | "\(.count)\t\(.slug)"
' | awk -F'\t' '{ printf "  %4d  %s\n", $1, $2 }'

TOTAL=$(echo "${NEW}" | jq '.insights | length')
echo "[backfill] total: ${TOTAL}"

if [[ "${APPLY}" -eq 1 ]]; then
  TS=$(date +%Y%m%d-%H%M%S)
  BACKUP="${INDEX}.bak-${TS}"
  cp "${INDEX}" "${BACKUP}"
  echo "${NEW}" > "${INDEX}"
  echo "[backfill] wrote ${INDEX}"
  echo "[backfill] backup at ${BACKUP}"
else
  echo "[backfill] dry-run (no changes). re-run with --apply to write."
fi
