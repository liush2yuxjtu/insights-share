#!/usr/bin/env bash
# sync-mirror.sh — pull / push the per-repo `<owner>/<repo>-insights` mirror.
#
# Per design doc:
#   Storage backend = GitHub mirror repo `<owner>/<repo>-insights` (separate
#   repo, same org). Raw jsonl committed plain (no LFS) into raw/<session>.jsonl.
#   Lesson metadata in mirror's root lessons.jsonl. ratings.jsonl for ratings.
#
# Subcommands:
#   pull <repo_slug>     git fetch + checkout latest mirror clone (background-safe)
#   push <repo_slug>     commit local lessons/ratings, push to mirror
#   ensure <repo_slug>   ensure clone exists at standard path (used by cold-start)
#   status <repo_slug>   print one-line summary {clone:bool, ahead:int, behind:int}
#
# Auth: reads PAT via pat-auth.sh (per design: per-repo fine-grained PAT).

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"
MIRROR_HOST="${INSIGHTS_MIRROR_HOST:-github.com}"

cmd="${1:-}"; shift || true
repo_slug="${1:-}"; shift || true
[[ -z "$cmd" || -z "$repo_slug" ]] && {
  sed -n '2,16p' "$0"
  exit 2
}

# Resolve owner/repo from slug (slug = host__owner__repo).
owner_repo=$(printf '%s' "$repo_slug" | python3 -c '
import sys
parts = sys.stdin.read().strip().split("__")
if len(parts) < 3: sys.exit(0)
print(f"{parts[1]}/{parts[2]}-insights")
')

[[ -z "$owner_repo" ]] && exit 0

mirror_dir="${INSIGHTS_ROOT}/${repo_slug}/.mirror"
local_lessons="${INSIGHTS_ROOT}/${repo_slug}/lessons.jsonl"
local_ratings="${INSIGHTS_ROOT}/${repo_slug}/ratings.jsonl"

mkdir -p "$(dirname "$mirror_dir")"

git_url() {
  local pat=""
  if [[ -x "${PLUGIN_ROOT}/scripts/pat-auth.sh" ]]; then
    pat=$(bash "${PLUGIN_ROOT}/scripts/pat-auth.sh" get "$repo_slug" 2>/dev/null || true)
  fi
  if [[ -n "$pat" ]]; then
    printf 'https://x-access-token:%s@%s/%s.git' "$pat" "$MIRROR_HOST" "$owner_repo"
  else
    printf 'https://%s/%s.git' "$MIRROR_HOST" "$owner_repo"
  fi
}

case "$cmd" in
  ensure)
    if [[ -d "$mirror_dir/.git" ]]; then
      printf '{"clone":true,"path":"%s"}\n' "$mirror_dir"
      exit 0
    fi
    url=$(git_url)
    if git clone --quiet --depth 50 "$url" "$mirror_dir" 2>/dev/null; then
      printf '{"clone":true,"path":"%s","fresh":true}\n' "$mirror_dir"
    else
      # Mirror does not exist yet — log warning & disable retrieval until
      # someone runs `gh repo create <owner>/<repo>-insights`.
      printf '{"clone":false,"reason":"mirror_not_found","hint":"gh repo create %s --private"}\n' "$owner_repo"
    fi
    ;;
  pull)
    [[ -d "$mirror_dir/.git" ]] || { bash "$0" ensure "$repo_slug"; }
    if [[ -d "$mirror_dir/.git" ]]; then
      ( cd "$mirror_dir" && git fetch --quiet origin 2>/dev/null && git reset --hard --quiet origin/HEAD 2>/dev/null ) || true
      printf '{"pulled":true}\n'
    else
      printf '{"pulled":false}\n'
    fi
    ;;
  push)
    bash "$0" ensure "$repo_slug" >/dev/null 2>&1 || true
    [[ -d "$mirror_dir/.git" ]] || { printf '{"pushed":false,"reason":"no_clone"}\n'; exit 0; }
    # Copy local files into mirror, append-only semantics.
    if [[ -f "$local_lessons" ]]; then
      mkdir -p "$mirror_dir"
      cat "$local_lessons" >> "$mirror_dir/lessons.jsonl"
      # Dedupe by id to keep file idempotent.
      F="$mirror_dir/lessons.jsonl" python3 -c '
import json, os, sys
path = os.environ["F"]
seen = set()
out = []
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        i = obj.get("id")
        if i in seen: continue
        seen.add(i)
        out.append(obj)
with open(path, "w") as fh:
    for obj in out:
        fh.write(json.dumps(obj) + "\n")
'
      : > "$local_lessons"
    fi
    if [[ -f "$local_ratings" ]]; then
      cat "$local_ratings" >> "$mirror_dir/ratings.jsonl"
      : > "$local_ratings"
    fi
    ( cd "$mirror_dir"
      git add lessons.jsonl ratings.jsonl 2>/dev/null || true
      [[ ! -d raw ]] || git add raw/ 2>/dev/null || true
      if ! git diff --cached --quiet 2>/dev/null; then
        git -c user.email="insights-share@localhost" \
            -c user.name="insights-share[bot]" \
            commit --quiet -m "insights: append from $(hostname) at $(date -u +%FT%TZ)" \
            >/dev/null 2>&1 || true
        git push --quiet origin HEAD 2>/dev/null || true
      fi
    ) || true
    printf '{"pushed":true}\n'
    ;;
  status)
    if [[ ! -d "$mirror_dir/.git" ]]; then
      printf '{"clone":false}\n'
      exit 0
    fi
    ahead=$(cd "$mirror_dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
    behind=$(cd "$mirror_dir" && git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    printf '{"clone":true,"ahead":%s,"behind":%s}\n' "$ahead" "$behind"
    ;;
  *)
    echo "ERROR: unknown subcommand $cmd" >&2
    exit 2
    ;;
esac
