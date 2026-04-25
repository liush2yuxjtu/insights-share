#!/usr/bin/env bash
# canonical-remote.sh — derive canonical <host>/<owner>/<repo> from any git
# remote URL (HTTPS or SSH). Strips .git suffix, lowercases host. Pure stdout.
#
# Usage:
#   canonical-remote.sh                       # uses cwd
#   canonical-remote.sh /path/to/repo
#   canonical-remote.sh --slug                # outputs repo-slug (host__owner__repo)
#   echo "git@github.com:Foo/Bar.git" | canonical-remote.sh --from-url
#
# Per design doc P4: same-git-remote is the privacy boundary; HTTPS/SSH must
# canonicalize identically. Used for buffer dir, mirror-repo name, retrieval
# scope.
#
# Outputs (default):
#   github.com/foo/bar
# Outputs (--slug):
#   github.com__foo__bar

set -euo pipefail

mode="canonical"
target=""
from_url_input=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)      mode="slug"; shift ;;
    --from-url)  from_url_input=$(cat); shift ;;
    --help|-h)
      sed -n '2,16p' "$0"
      exit 0 ;;
    *)           target="$1"; shift ;;
  esac
done

normalize_url() {
  local url="$1"
  [[ -z "$url" ]] && return 1

  # Strip trailing whitespace
  url="${url%$'\r'}"
  url="${url//[[:space:]]/}"

  local host="" path=""
  if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
    # SSH form: git@github.com:owner/repo.git
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^ssh://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
    # Strip user@ from host
    host="${host#*@}"
  elif [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
    # Strip user:pass@
    host="${host#*@}"
  else
    return 1
  fi

  # Lowercase host
  host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
  # Strip default port :22 :443
  host="${host%:22}"
  host="${host%:443}"
  # Strip trailing slash
  path="${path%/}"
  # Strip .git suffix
  path="${path%.git}"
  # Lowercase entire path for case-insensitive matching (GitHub is)
  path=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')

  printf '%s/%s\n' "$host" "$path"
}

if [[ -n "$from_url_input" ]]; then
  canonical=$(normalize_url "$from_url_input") || { echo "ERROR: invalid url" >&2; exit 2; }
else
  cwd="${target:-$PWD}"
  cd "$cwd" 2>/dev/null || { echo "ERROR: cwd $cwd not accessible" >&2; exit 2; }
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: not a git repository" >&2
    exit 2
  fi
  url=$(git remote get-url origin 2>/dev/null || true)
  [[ -z "$url" ]] && { echo "ERROR: no origin remote" >&2; exit 2; }
  canonical=$(normalize_url "$url") || { echo "ERROR: cannot parse $url" >&2; exit 2; }
fi

if [[ "$mode" == "slug" ]]; then
  printf '%s\n' "${canonical//\//__}"
else
  printf '%s\n' "$canonical"
fi
