#!/usr/bin/env bats
# install-statusline.sh / uninstall-statusline.sh idempotency.

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  INSTALL="${REPO_ROOT}/scripts/install-statusline.sh"
  UNINSTALL="${REPO_ROOT}/scripts/uninstall-statusline.sh"
  TMP_CFG="$(mktemp -d)"
  export CLAUDE_CONFIG_DIR="${TMP_CFG}"
}

teardown() {
  rm -rf "${TMP_CFG}"
}

read_cmd() {
  node -e "const s=JSON.parse(require('fs').readFileSync('${TMP_CFG}/settings.json','utf8'));process.stdout.write((s.statusLine&&s.statusLine.command)||'')"
}

@test "fresh install on empty settings creates statusLine" {
  run bash "${INSTALL}"
  [ "$status" -eq 0 ]
  cmd="$(read_cmd)"
  [[ "${cmd}" == *"insights-share-pulse"* ]]
  [[ "${cmd}" == *"statusline-pulse.sh"* ]]
}

@test "second install is a no-op (idempotent)" {
  bash "${INSTALL}" >/dev/null
  cmd1="$(read_cmd)"
  bash "${INSTALL}" >/dev/null
  cmd2="$(read_cmd)"
  [ "${cmd1}" = "${cmd2}" ]
}

@test "postfix mode preserves existing statusLine command" {
  printf '{"statusLine":{"type":"command","command":"bash /existing.sh"}}\n' > "${TMP_CFG}/settings.json"
  bash "${INSTALL}" >/dev/null
  cmd="$(read_cmd)"
  [[ "${cmd}" == *"/existing.sh"* ]]
  [[ "${cmd}" == *"insights-share-pulse"* ]]
  [[ "${cmd}" == *";"* ]]
}

@test "solo mode replaces existing statusLine command" {
  printf '{"statusLine":{"type":"command","command":"bash /existing.sh"}}\n' > "${TMP_CFG}/settings.json"
  bash "${INSTALL}" --solo >/dev/null
  cmd="$(read_cmd)"
  [[ "${cmd}" != *"/existing.sh"* ]]
  [[ "${cmd}" == *"insights-share-pulse"* ]]
}

@test "uninstall after postfix install restores the prior command" {
  printf '{"statusLine":{"type":"command","command":"bash /existing.sh"}}\n' > "${TMP_CFG}/settings.json"
  bash "${INSTALL}" >/dev/null
  bash "${UNINSTALL}" >/dev/null
  cmd="$(read_cmd)"
  [ "${cmd}" = "bash /existing.sh" ]
}

@test "uninstall after solo install removes statusLine entirely" {
  bash "${INSTALL}" --solo >/dev/null
  bash "${UNINSTALL}" >/dev/null
  run node -e "const s=JSON.parse(require('fs').readFileSync('${TMP_CFG}/settings.json','utf8'));process.stdout.write(s.statusLine?'YES':'NO')"
  [ "$output" = "NO" ]
}

@test "force re-wires even when marker present" {
  bash "${INSTALL}" >/dev/null
  cmd1="$(read_cmd)"
  run bash "${INSTALL}" --force
  [ "$status" -eq 0 ]
  cmd2="$(read_cmd)"
  # Re-wire produces same command (no duplicate marker)
  count=$(printf '%s' "${cmd2}" | grep -o "insights-share-pulse" | wc -l | tr -d ' ')
  [ "${count}" = "1" ]
}
