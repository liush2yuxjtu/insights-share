#!/bin/bash
# duck-claude-launch.sh — opens a Claude Code REPL inside a sandbox HOME so a
# duck user can install/use the insights-share statusline badge purely by
# talking. Never asks the duck to type a bash command.
#
# Auth: we mirror the user's `claudefast` env (MiniMax API key, base URL,
# model overrides) so Claude skips the OAuth login wizard entirely. The
# token is read from the user's local zsh shell snapshot at runtime — it is
# NEVER committed to this script.
#
# Sandbox: HOME and CLAUDE_CONFIG_DIR are pinned to /tmp/duck-pulse-sandbox.
# install-statusline.sh / uninstall-statusline.sh detect the sandbox via
# the `.sandbox-marker` file and refuse production unless --allow-production.

set -e

SANDBOX_ROOT="${SANDBOX_ROOT:-/tmp/duck-pulse-sandbox}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ORIG_HOME="${HOME}"

case "${SANDBOX_ROOT}" in
  /tmp/*|/var/folders/*|/private/tmp/*) ;;
  *)
    echo "ERROR: SANDBOX_ROOT must live under /tmp or /var/folders." >&2
    exit 1
    ;;
esac

# --- 1. Bootstrap sandbox files (if marker missing) -------------------------
if [ ! -f "${SANDBOX_ROOT}/.sandbox-marker" ]; then
  SANDBOX_ROOT="${SANDBOX_ROOT}" source "${SCRIPT_DIR}/sandbox-bootstrap.sh" >/dev/null
fi

# --- 2. Mirror claudefast env (token from user's local snapshot) ------------
# We pull from the most recent zsh snapshot under the user's REAL ~/.claude.
SNAP="$(ls -t "${ORIG_HOME}/.claude/shell-snapshots/snapshot-zsh-"*.sh 2>/dev/null | head -1)"
if [ -z "${SNAP}" ] || [ ! -f "${SNAP}" ]; then
  echo "ERROR: no claudefast shell snapshot found at ${ORIG_HOME}/.claude/shell-snapshots/" >&2
  echo "       Run 'claudefast -h' once in your real shell to generate one, then retry." >&2
  exit 2
fi
MINIMAX_TOKEN="$(grep -oE 'minimax_token="[^"]+"' "${SNAP}" | head -1 | cut -d'"' -f2)"
if [ -z "${MINIMAX_TOKEN}" ]; then
  echo "ERROR: could not extract minimax_token from ${SNAP}." >&2
  exit 2
fi
export ANTHROPIC_API_KEY="${MINIMAX_TOKEN}"
unset ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="https://api.minimaxi.com/anthropic"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="MiniMax-M2.7-highspeed"
export ANTHROPIC_DEFAULT_OPUS_MODEL="MiniMax-M2.7-highspeed"
export ANTHROPIC_DEFAULT_SONNET_MODEL="MiniMax-M2.7-highspeed"
export ANTHROPIC_MODEL="MiniMax-M2.7-highspeed"
export API_TIMEOUT_MS="3000000"
export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING="1"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export ENABLE_CLAUDEAI_MCP_SERVERS="false"
export MCP_CONNECTION_NONBLOCKING="true"
export INSIGHTS_CAPTURE_DISABLED="1"

# --- 3. Pin HOME + CLAUDE_CONFIG_DIR to the sandbox -------------------------
export HOME="${SANDBOX_ROOT}"
export CLAUDE_CONFIG_DIR="${SANDBOX_ROOT}/.claude-minimax"
mkdir -p "${CLAUDE_CONFIG_DIR}"

# Last 20 chars of the API token — this is the key Claude uses to remember
# that this token was approved (so the "Detected a custom API key" wizard
# doesn't fire).
TOKEN_TAIL="${MINIMAX_TOKEN: -20}"

# Seed onboarding flags so the duck never sees the first-run wizard.
for cfgdir in "${HOME}/.claude" "${CLAUDE_CONFIG_DIR}"; do
  mkdir -p "${cfgdir}"
  cat > "${cfgdir}/settings.json" <<EOF
{
  "theme": "dark",
  "hasCompletedOnboarding": true,
  "hasCompletedProjectOnboarding": true,
  "hasTrustDialogAccepted": true,
  "skipDangerousModePermissionPrompt": true
}
EOF
done

# .claude.json lives at BOTH $HOME and $CLAUDE_CONFIG_DIR depending on the
# Claude Code version. Seed both so the wizard never fires.
SEED_JSON=$(cat <<EOF
{
  "numStartups": 1,
  "hasCompletedOnboarding": true,
  "hasTrustDialogAccepted": true,
  "lastOnboardingVersion": "999.0.0",
  "lastReleaseNotesSeen": "999.0.0",
  "userID": "duck-sandbox",
  "firstStartTime": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "officialMarketplaceAutoInstallAttempted": true,
  "officialMarketplaceAutoInstalled": true,
  "opusProMigrationComplete": true,
  "sonnet1m45MigrationComplete": true,
  "migrationVersion": 999,
  "customApiKeyResponses": {
    "approved": ["${TOKEN_TAIL}"],
    "rejected": []
  },
  "projects": {
    "${PLUGIN_DIR}": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true,
      "projectOnboardingSeenCount": 1,
      "hasClaudeMdExternalIncludesApproved": true,
      "hasClaudeMdExternalIncludesWarningShown": true,
      "allowedTools": ["Bash"],
      "mcpContextUris": [],
      "mcpServers": {},
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": []
    }
  }
}
EOF
)
printf '%s' "${SEED_JSON}" > "${HOME}/.claude.json"
printf '%s' "${SEED_JSON}" > "${CLAUDE_CONFIG_DIR}/.claude.json"

# --- 4. Friendly welcome banner --------------------------------------------
clear
cat <<'BANNER'
   __
  <(o )___    呱！欢迎来到 Pulse 鸭鸭沙盒。
   ( ._> /    完整指南：docs/duck-install-guide-zh.md
    `---'

🦆 你现在已经在沙盒里了 —— HOME 和 CLAUDE_CONFIG_DIR 都被改向 /tmp。
   通过 MiniMax 模型对话，无需登录。
   你只要打字跟它说话就行。

────────────────────────────────────────────────────────────────────
 鸭鸭可以这样跟 Claude 说：

   ▸ 我在哪？                        （自检沙盒）
   ▸ 装徽章                          （安装 statusline）
   ▸ 看一眼徽章长啥样                （渲染一次）
   ▸ 鸭鸭状态总览                    （看完整情况）
   ▸ 关徽章                          （卸载）

 不会用就直接说：「鸭鸭迷路了，告诉我能干啥」
 —— Claude 会照着 SKILL.md 的 trigger 列表回你。
────────────────────────────────────────────────────────────────────

❌ 千万别做的事：
   • 不要直接打 bash 命令 —— 你不需要会 bash
   • 不要去碰真家 /Users/m1/.claude —— 沙盒只在 /tmp/duck-pulse-sandbox

正在启动 Claude Code (MiniMax-M2.7-highspeed)…
BANNER

sleep 2

# --- 5. Hand off to claude (no nested shells) ------------------------------
APPEND_PROMPT='你正在帮一只可爱的鸭子用户操作 insights-share statusline 插件。鸭子只会说中文，不会用 bash。所有底层命令都通过 /insights-pulse 这个 slash command 完成。每次执行任何 /insights-pulse 子命令前，先用一句话告诉鸭子你要做啥；执行完后用一句话总结结果。如果鸭子的话能匹配到 insights-pulse skill 的 trigger 描述，自动调用 /insights-pulse。检测到当前 HOME 不在 /tmp 下（即鸭子不在沙盒）时，立刻停下并提醒鸭子关掉窗口。'

exec claude \
  --plugin-dir "${PLUGIN_DIR}" \
  --add-dir "${PLUGIN_DIR}" \
  --permission-mode bypassPermissions \
  --append-system-prompt "${APPEND_PROMPT}"
