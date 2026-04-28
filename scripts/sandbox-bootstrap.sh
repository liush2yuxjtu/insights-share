#!/bin/bash
# sandbox-bootstrap.sh — build a throwaway HOME + CLAUDE_CONFIG_DIR for testing
# the insights-share statusline pulse badge without touching real user state.
#
# Usage (source it so env exports stick):
#   source scripts/sandbox-bootstrap.sh           # uses /tmp/duck-pulse-sandbox
#   SANDBOX_ROOT=/tmp/my-box source scripts/sandbox-bootstrap.sh
#
# What it does:
#   1. Wipes & recreates ${SANDBOX_ROOT} as a fresh fake HOME
#   2. Drops a `.sandbox-marker` so the install/uninstall scripts detect it
#   3. Builds a minimal ~/.claude-team layout with a tiny fake index
#   4. Exports HOME, CLAUDE_CONFIG_DIR, INSIGHTS_PLUGIN_DIR for the rest of the shell

SANDBOX_ROOT="${SANDBOX_ROOT:-/tmp/duck-pulse-sandbox}"

if [ "${SANDBOX_ROOT}" = "/" ] || [ "${SANDBOX_ROOT}" = "${HOME}" ] || [ -z "${SANDBOX_ROOT}" ]; then
  echo "ERROR: refusing dangerous SANDBOX_ROOT=${SANDBOX_ROOT}" >&2
  return 1 2>/dev/null || exit 1
fi

case "${SANDBOX_ROOT}" in
  /tmp/*|/var/folders/*|/private/tmp/*) ;;
  *)
    echo "ERROR: SANDBOX_ROOT must live under /tmp or /var/folders to avoid clobbering real dirs." >&2
    echo "       Got: ${SANDBOX_ROOT}" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

if [ -d "${SANDBOX_ROOT}" ]; then
  echo "[sandbox] wiping existing ${SANDBOX_ROOT}"
  rm -rf "${SANDBOX_ROOT}"
fi

mkdir -p "${SANDBOX_ROOT}/.claude" \
         "${SANDBOX_ROOT}/.claude-team/insights/staging" \
         "${SANDBOX_ROOT}/.claude-team/insights/raw" \
         "${SANDBOX_ROOT}/.claude-team/cache/peer-indexes" \
         "${SANDBOX_ROOT}/.claude-team/config" \
         "${SANDBOX_ROOT}/.claude-team/logs"

# Marker so install-statusline.sh / uninstall-statusline.sh light up green.
date '+sandbox created %Y-%m-%dT%H:%M:%S' > "${SANDBOX_ROOT}/.sandbox-marker"

# Tiny fake index (3 entries, mixed topic_slugs)
cat > "${SANDBOX_ROOT}/.claude-team/insights/index.json" <<'EOF'
{"insights":[
  {"name":"jsonl smoke test 用 mtime 倒序","when_to_use":"处理 jsonl session 文件","description":"用 ls -t 按 mtime 倒序","uploader":"duck","uploader_ip":"127.0.0.1","topic_slug":"jsonl-ingestion","created_at":"2026-04-28T00:00:00Z"},
  {"name":"don't mock the database in integration tests","when_to_use":"writing integration tests","description":"hit a real DB instead","uploader":"duck","uploader_ip":"127.0.0.1","topic_slug":"testing","created_at":"2026-04-28T00:01:00Z"},
  {"name":"a stray uncategorized lesson","when_to_use":"placeholder","description":"placeholder","uploader":"duck","uploader_ip":"127.0.0.1","topic_slug":"uncategorized","created_at":"2026-04-28T00:02:00Z"}
]}
EOF

# No teammates configured by default → rsync-pull.sh will write STATE=NOCFG.
# To experiment with peer pulls, copy teammates.example.json over.
cp "$(dirname "${BASH_SOURCE[0]}")/../config/teammates.example.json" \
   "${SANDBOX_ROOT}/.claude-team/config/teammates.example.json"

# Resolve plugin dir (the insights-share root the bootstrap script lives inside)
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Export to caller's shell (only effective when sourced)
export HOME="${SANDBOX_ROOT}"
export CLAUDE_CONFIG_DIR="${SANDBOX_ROOT}/.claude"
export INSIGHTS_PLUGIN_DIR="${PLUGIN_DIR}"

# Friendly summary
cat <<EOF
[sandbox] ✓ ready
  HOME              = ${HOME}
  CLAUDE_CONFIG_DIR = ${CLAUDE_CONFIG_DIR}
  INSIGHTS_PLUGIN_DIR = ${INSIGHTS_PLUGIN_DIR}
  fake index        = \$HOME/.claude-team/insights/index.json (3 entries)
  marker            = \$HOME/.sandbox-marker

next:
  bash \$INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh --check    # confirm 🦆 SANDBOX banner
  bash \$INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh            # wire badge into sandbox settings.json
  bash \$INSIGHTS_PLUGIN_DIR/scripts/rsync-pull.sh                    # populate vault + pipe flags (no real rsync)
  bash \$INSIGHTS_PLUGIN_DIR/scripts/query-insights.sh "jsonl"         # populate hit flag (matches fake fixture → 1 hit)
  bash \$INSIGHTS_PLUGIN_DIR/scripts/statusline-pulse.sh; echo        # render the badge
EOF
