---
description: Inspect / control the insights-share statusline badge (status / on / off / reset / render)
argument-hint: "[status|on|solo|off|reset|render]"
---

# /insights-pulse

Run via the `insights-pulse` skill. Default subcommand is `status`.

Args: `$ARGUMENTS`

## Routing

```bash
ARG="${1:-status}"
ROOT="${CLAUDE_PLUGIN_ROOT}"
TEAM_DIR="${HOME}/.claude-team"

case "${ARG}" in
  on)     bash "${ROOT}/scripts/install-statusline.sh" ;;
  solo)   bash "${ROOT}/scripts/install-statusline.sh" --solo ;;
  off)    bash "${ROOT}/scripts/uninstall-statusline.sh" ;;
  reset)
    rm -f "${TEAM_DIR}/.pulse-hit" "${TEAM_DIR}/.pulse-sync" "${TEAM_DIR}/.pulse-pipe"
    echo "[insights-pulse] flags cleared; next SessionStart / UserPromptSubmit hook will repopulate"
    ;;
  render) bash "${ROOT}/scripts/statusline-pulse.sh"; echo ;;
  status|*)
    echo "insights-pulse — current state"
    for f in pulse-hit pulse-sync pulse-pipe; do
      p="${TEAM_DIR}/.${f}"
      if [ -f "${p}" ] && [ ! -L "${p}" ]; then
        printf '  %-12s %s\n' "${f}:" "$(head -c 64 "${p}")"
      else
        printf '  %-12s (missing)\n' "${f}:"
      fi
    done
    printf '  badge:       '
    bash "${ROOT}/scripts/statusline-pulse.sh"
    echo
    ;;
esac
```
