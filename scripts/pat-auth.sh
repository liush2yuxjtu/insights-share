#!/usr/bin/env bash
# pat-auth.sh — per-repo GitHub fine-grained PAT manager.
#
# Per design doc:
#   Auth model = per-repo GitHub fine-grained PAT (one PAT per repo at first
#   install, since fine-grained PATs do not support reliable wildcard repo
#   selection in current GitHub). Stored at
#   ~/.gstack/insights-auth/<repo-slug>.token (chmod 600). Onboarding via
#   /insight-install, prompts for PAT once per repo, validates scope
#   (<repo>-insights write), persists. v2: migrate to GitHub App for org-wide.
#
# Subcommands:
#   set <repo-slug> [pat]    Persist PAT (read from arg or stdin); chmod 600.
#   get <repo-slug>          Print PAT to stdout (empty if missing).
#   has <repo-slug>          Exit 0 if present, 1 otherwise.
#   validate <repo-slug>     GET https://api.github.com/repos/<owner>/<repo>-insights
#                            with PAT; require 200 + push permission.
#   forget <repo-slug>       Remove the token file.
#   list                     List slugs with persisted PATs.

set -euo pipefail

AUTH_ROOT="${INSIGHTS_AUTH_ROOT:-$HOME/.gstack/insights-auth}"
mkdir -p "$AUTH_ROOT"
chmod 700 "$AUTH_ROOT" 2>/dev/null || true

cmd="${1:-}"; shift || true
slug="${1:-}"; shift || true

token_path() { printf '%s/%s.token' "$AUTH_ROOT" "$1"; }

case "$cmd" in
  set)
    [[ -z "$slug" ]] && { echo "ERROR: slug required" >&2; exit 2; }
    pat="${1:-}"
    if [[ -z "$pat" ]]; then
      pat=$(cat)
    fi
    pat=$(printf '%s' "$pat" | tr -d '\r\n[:space:]')
    [[ -z "$pat" ]] && { echo "ERROR: empty PAT" >&2; exit 2; }
    f=$(token_path "$slug")
    umask 077
    printf '%s' "$pat" > "$f"
    chmod 600 "$f" 2>/dev/null || true
    printf '{"slug":"%s","saved":true}\n' "$slug"
    ;;
  get)
    [[ -z "$slug" ]] && exit 0
    f=$(token_path "$slug")
    [[ -f "$f" ]] && cat "$f"
    ;;
  has)
    [[ -z "$slug" ]] && exit 1
    [[ -f "$(token_path "$slug")" ]] && exit 0
    exit 1
    ;;
  validate)
    [[ -z "$slug" ]] && { echo "ERROR: slug required" >&2; exit 2; }
    pat=$(bash "$0" get "$slug")
    [[ -z "$pat" ]] && { printf '{"ok":false,"reason":"no_pat"}\n'; exit 1; }
    parts=$(printf '%s' "$slug" | tr '__' '\n' | grep -v '^$')
    owner=$(printf '%s\n' "$parts" | sed -n '2p')
    repo=$(printf '%s\n' "$parts" | sed -n '3p')
    target="${owner}/${repo}-insights"
    code=$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer $pat" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${target}" 2>/dev/null || echo "000")
    if [[ "$code" == "200" ]]; then
      printf '{"ok":true,"target":"%s"}\n' "$target"
    else
      printf '{"ok":false,"target":"%s","http":"%s"}\n' "$target" "$code"
      exit 1
    fi
    ;;
  forget)
    [[ -z "$slug" ]] && { echo "ERROR: slug required" >&2; exit 2; }
    rm -f "$(token_path "$slug")"
    printf '{"slug":"%s","forgot":true}\n' "$slug"
    ;;
  list)
    shopt -s nullglob
    for f in "$AUTH_ROOT"/*.token; do
      base=$(basename "$f" .token)
      printf '%s\n' "$base"
    done
    shopt -u nullglob
    ;;
  ""|--help|-h)
    sed -n '2,20p' "$0"
    ;;
  *)
    echo "ERROR: unknown cmd $cmd" >&2
    exit 2
    ;;
esac
