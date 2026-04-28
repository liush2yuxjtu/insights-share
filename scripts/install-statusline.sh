#!/bin/bash
# install-statusline.sh — wire insights-share badge into ~/.claude/settings.json
#
# Operates in POSTFIX mode by default: any existing statusLine command stays,
# and our badge runs after it. Idempotent — running twice is a no-op.
# Backs up settings.json to settings.json.bak before each run.
#
# Usage:
#   bash install-statusline.sh           # postfix mode (recommended)
#   bash install-statusline.sh --solo    # replace existing statusLine entirely
#   bash install-statusline.sh --force   # rewrite even if already wired
set -e

MODE="postfix"
FORCE=0
for arg in "$@"; do
  case "${arg}" in
    --solo)    MODE="solo" ;;
    --postfix) MODE="postfix" ;;
    --force|-f) FORCE=1 ;;
    *) echo "unknown flag: ${arg}" >&2; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is required (used to merge settings.json safely)." >&2
  exit 1
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
SETTINGS="${CLAUDE_DIR}/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULSE="${SCRIPT_DIR}/statusline-pulse.sh"
MARKER="# insights-share-pulse"

mkdir -p "${CLAUDE_DIR}"
[ ! -f "${SETTINGS}" ] && echo '{}' > "${SETTINGS}"
cp "${SETTINGS}" "${SETTINGS}.bak"

PULSE_PATH="${PULSE}" SETTINGS_PATH="${SETTINGS}" MODE="${MODE}" FORCE="${FORCE}" MARKER="${MARKER}" \
node <<'EOF'
const fs = require('fs');
const settingsPath = process.env.SETTINGS_PATH;
const pulsePath    = process.env.PULSE_PATH;
const mode         = process.env.MODE;
const force        = process.env.FORCE === '1';
const marker       = process.env.MARKER;

const s = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
const pulseInvocation = `bash "${pulsePath}"`;
const taggedPulse = `${pulseInvocation} ${marker}`;

const existing = s.statusLine;
let existingCmd = '';
if (typeof existing === 'string') existingCmd = existing;
else if (existing && typeof existing.command === 'string') existingCmd = existing.command;

const alreadyWired = existingCmd.includes(marker);
if (alreadyWired && !force) {
  console.log(JSON.stringify({ status: 'noop', reason: 'already wired', command: existingCmd }));
  process.exit(0);
}

let newCmd;
if (mode === 'solo' || existingCmd === '') {
  newCmd = taggedPulse;
} else {
  // strip any prior pulse insertion (force re-wire)
  const stripped = existingCmd.replace(new RegExp(`\\s*;?\\s*bash\\s+["']?[^"']*statusline-pulse\\.sh["']?\\s+${marker}\\s*`, 'g'), '').replace(/;\s*$/, '').trim();
  newCmd = `${stripped}; ${taggedPulse}`;
}

s.statusLine = { type: 'command', command: newCmd };
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log(JSON.stringify({ status: 'wired', mode: mode, command: newCmd }));
EOF

echo "[insights-share] statusLine wired (${MODE}). Backup: ${SETTINGS}.bak"
echo "[insights-share] Restart Claude Code to pick up the change."
