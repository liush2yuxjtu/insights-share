#!/usr/bin/env bash
# zero-start-claude-uat.sh — README prompt + tmux sandbox UAT for
# insights-share. Default mode is deterministic and non-interactive. Set
# ZERO_START_RUN_CLAUDE=1 to also open Claude Code in tmux and paste the
# README prompt for a human-observed run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"
HELP="$ROOT/skills/insight-help/SKILL.md"
WELCOME="$ROOT/scripts/append-claude-md.sh"
ARTIFACT_ROOT="${ZERO_START_ARTIFACT_ROOT:-${TMPDIR:-/tmp}/insights-zero-start-$$}"
PROMPT_FILE="$ARTIFACT_ROOT/readme-install-prompt.txt"
SESSION="insights-zero-start-$$"

PASS=0
FAIL=0
STEP=0
mkdir -p "$ARTIFACT_ROOT"

step() { STEP=$((STEP + 1)); printf '\n-- zero-start step %02d: %s --\n' "$STEP" "$1"; }
ok() { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
ko() { printf '  fail: %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  skip: %s\n' "$1"; }

contains() {
  local file="$1" needle="$2" desc="$3"
  if grep -Fq -- "$needle" "$file"; then ok "$desc"; else ko "$desc"; fi
}

extract_prompt() {
  awk '
    /<!-- zero-start-claude-install-prompt:start -->/ {in_block=1; next}
    /<!-- zero-start-claude-install-prompt:end -->/ {in_block=0; found=1}
    in_block {print}
    END {exit found ? 0 : 1}
  ' "$README" > "$PROMPT_FILE"
}

step "extract README copy-paste Claude Code prompt"
if extract_prompt && [[ -s "$PROMPT_FILE" ]]; then
  ok "README exposes marked install prompt at $PROMPT_FILE"
else
  ko "README is missing zero-start prompt markers"
fi

step "prompt installs only through claude plugin commands"
contains "$PROMPT_FILE" "claude plugin marketplace add liush2yuxjtu/insights-share" "marketplace add command present"
contains "$PROMPT_FILE" "claude plugin install insights-share@insights-share" "install command present"
contains "$PROMPT_FILE" "claude plugin enable insights-share@insights-share" "enable command present"
if grep -Eq '(^|[[:space:]])/plugin[[:space:]]+install|^[[:space:]]*install[[:space:]]+insights-share@' "$PROMPT_FILE"; then
  ko "prompt contains forbidden non-claude-plugin install wording"
else
  ok "prompt avoids slash-command or bare install instructions"
fi
bad_plugin_lines=$(grep -En 'plugin (marketplace|install|enable|uninstall|update)' "$PROMPT_FILE" \
  | grep -Ev '^[0-9]+:[[:space:]]*(claude plugin|`claude plugin|[-*] `claude plugin)' || true)
if [[ -z "$bad_plugin_lines" ]]; then
  ok "all plugin install lines start with claude plugin"
else
  ko "plugin command lines without claude prefix: $bad_plugin_lines"
fi

step "prompt explains fresh-session and onboarding flow"
contains "$PROMPT_FILE" "fresh Claude Code session" "fresh session requirement present"
contains "$PROMPT_FILE" "/insight-help" "help command present"
contains "$PROMPT_FILE" "statusline" "statusline guidance present"
contains "$PROMPT_FILE" "/insight-rate" "Gate 1 rating command present"
contains "$PROMPT_FILE" "Gate 1" "Gate 1 office-hours wording present"

step "/insight-help card contains statusline and Gate 1 usage"
contains "$HELP" "📊 Wire the statusline" "help card statusline section present"
contains "$HELP" "/insight-rate <lesson-id> <good|bad|irrelevant>" "help card rating syntax present"
contains "$HELP" "Gate 1" "help card Gate 1 wording present"

step "SessionStart welcome contains full zero-start guidance"
contains "$WELCOME" "Sixteen slash commands" "welcome lists sixteen commands"
contains "$WELCOME" "Statusline" "welcome includes statusline section"
contains "$WELCOME" "/insight-rate <lesson-id> good" "welcome includes rating example"
contains "$WELCOME" "Gate 1" "welcome includes Gate 1 wording"

step "tmux sandbox agent driver"
if ! command -v tmux >/dev/null 2>&1; then
  if [[ "${ZERO_START_ALLOW_NO_TMUX:-0}" == "1" ]]; then
    skip "tmux missing and ZERO_START_ALLOW_NO_TMUX=1"
  else
    ko "tmux is required for zero-start UAT"
  fi
else
  SANDBOX="$ARTIFACT_ROOT/sandbox-project"
  mkdir -p "$SANDBOX"
  printf '# zero-start sandbox\n' > "$SANDBOX/CLAUDE.md"
  tmux new-session -d -s "$SESSION" \
    "unset CLAUDE_PLUGIN_ROOT INSIGHTS_SERVER_URL INSIGHTS_CACHE_PATH INSIGHTS_OUTBOX_DIR; cd '$SANDBOX'; test -z \"\$CLAUDE_PLUGIN_ROOT\"; cp '$PROMPT_FILE' ./copied-prompt.txt; printf READY > '$ARTIFACT_ROOT/tmux.ready'; exit 0" \
    >/dev/null 2>&1
  for _ in $(seq 1 80); do [[ -f "$ARTIFACT_ROOT/tmux.ready" ]] && break; sleep 0.1; done
  if [[ -f "$ARTIFACT_ROOT/tmux.ready" && -s "$SANDBOX/copied-prompt.txt" ]]; then
    ok "tmux sandbox copied README prompt without leaked plugin env"
  else
    ko "tmux sandbox did not produce expected prompt artifact"
  fi
  tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true
fi

step "optional live Claude Code paste"
if [[ "${ZERO_START_RUN_CLAUDE:-0}" != "1" ]]; then
  skip "set ZERO_START_RUN_CLAUDE=1 to open Claude Code in tmux and paste the prompt"
elif ! command -v claude >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
  ko "live mode requires claude and tmux on PATH"
else
  LIVE_SESSION="${SESSION}-claude"
  SANDBOX="$ARTIFACT_ROOT/live-sandbox"
  mkdir -p "$SANDBOX"
  printf '# live zero-start sandbox\n' > "$SANDBOX/CLAUDE.md"
  tmux new-session -d -s "$LIVE_SESSION" "cd '$SANDBOX'; claude"
  sleep "${ZERO_START_CLAUDE_BOOT_WAIT:-3}"
  tmux load-buffer -b zero-start "$PROMPT_FILE"
  tmux paste-buffer -b zero-start -t "$LIVE_SESSION"
  tmux send-keys -t "$LIVE_SESSION" Enter
  sleep "${ZERO_START_CLAUDE_OBSERVE_WAIT:-8}"
  tmux capture-pane -p -t "$LIVE_SESSION" > "$ARTIFACT_ROOT/live-claude-pane.txt"
  if grep -Eiq 'insights-share|claude plugin|fresh Claude Code session' "$ARTIFACT_ROOT/live-claude-pane.txt"; then
    ok "live Claude pane received zero-start prompt"
  else
    ko "live Claude pane did not show expected prompt/install text"
  fi
  tmux kill-session -t "$LIVE_SESSION" >/dev/null 2>&1 || true
fi

printf '\nzero-start UAT: PASS=%d FAIL=%d artifacts=%s\n' "$PASS" "$FAIL" "$ARTIFACT_ROOT"
exit "$FAIL"
