#!/bin/bash
# uninstall-statusline.sh — reverse install-statusline.sh.
# Strips the marked pulse invocation from settings.json. If nothing else is
# left in statusLine.command, removes the statusLine field entirely so Claude
# Code falls back to default.
set -e

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node required." >&2
  exit 1
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
SETTINGS="${CLAUDE_DIR}/settings.json"
MARKER="# insights-share-pulse"

if [ ! -f "${SETTINGS}" ]; then
  echo "[insights-share] no settings.json at ${SETTINGS}; nothing to do."
  exit 0
fi

cp "${SETTINGS}" "${SETTINGS}.bak"

SETTINGS_PATH="${SETTINGS}" MARKER="${MARKER}" node <<'EOF'
const fs = require('fs');
const settingsPath = process.env.SETTINGS_PATH;
const marker = process.env.MARKER;
const s = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
const e = s.statusLine;
if (!e) { console.log(JSON.stringify({status:'noop'})); process.exit(0); }
let cmd = (typeof e === 'string') ? e : (e.command || '');
const stripped = cmd.replace(new RegExp(`\\s*;?\\s*bash\\s+["']?[^"']*statusline-pulse\\.sh["']?\\s+${marker}\\s*`, 'g'), '').replace(/^\s*;\s*/, '').replace(/\s*;\s*$/, '').trim();
if (stripped === '') { delete s.statusLine; }
else { s.statusLine = { type: 'command', command: stripped }; }
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log(JSON.stringify({status:'unwired', command: stripped || null}));
EOF

echo "[insights-share] statusLine unwired. Backup: ${SETTINGS}.bak"
