---
description: 控制 insights-share 三段折叠状态栏徽章（自检 / 安装 / 卸载 / 渲染 / 重置）
argument-hint: "[check|status|on|solo|off|reset|render]"
---

# /insights-pulse

无参数时默认走 `status`：先打沙盒/生产横幅，再列三个 flag，再渲染徽章。
鸭鸭友好：每一段都附中文解读。

Args: `$ARGUMENTS`

## 路由

```bash
ARG="${1:-status}"
ROOT="${CLAUDE_PLUGIN_ROOT}"
TEAM_DIR="${HOME}/.claude-team"

# 把沙盒/生产横幅当作每个非破坏性子命令的开场白，让鸭子永远先看清自己在哪
print_banner() {
  bash "${ROOT}/scripts/install-statusline.sh" --check 2>&1 | sed 's/^/  /'
}

case "${ARG}" in
  check)
    echo "🦆 鸭鸭自检：你在哪个家？"
    print_banner
    ;;

  on)
    echo "🦆 鸭鸭装徽章（保留你原来的状态栏，把徽章拼到末尾）"
    bash "${ROOT}/scripts/install-statusline.sh"
    echo "  下一步：跟 Claude 说「重启 Claude Code」或自己关掉再开，徽章才会出现。"
    ;;

  solo)
    echo "🦆 鸭鸭独占模式（替换原状态栏，只剩徽章）"
    bash "${ROOT}/scripts/install-statusline.sh" --solo
    ;;

  off)
    echo "🦆 鸭鸭卸徽章"
    bash "${ROOT}/scripts/uninstall-statusline.sh"
    ;;

  reset)
    echo "🦆 鸭鸭把三个 flag 文件清掉，下次 hook 触发会重建"
    rm -f "${TEAM_DIR}/.pulse-hit" "${TEAM_DIR}/.pulse-sync" "${TEAM_DIR}/.pulse-pipe"
    echo "  done."
    ;;

  render)
    echo "🦆 鸭鸭看一眼徽章长啥样："
    printf '  '
    bash "${ROOT}/scripts/statusline-pulse.sh"
    echo
    ;;

  status|*)
    echo "🦆 鸭鸭状态总览"
    echo
    echo "[一] 你在哪个家？"
    print_banner
    echo
    echo "[二] 三个 flag 文件（徽章读这些）："
    for f in pulse-hit pulse-sync pulse-pipe; do
      p="${TEAM_DIR}/.${f}"
      if [ -f "${p}" ] && [ ! -L "${p}" ]; then
        printf '  %-12s %s\n' "${f}:" "$(head -c 64 "${p}")"
      else
        printf '  %-12s (还没有，跑一次 hook 就会出现)\n' "${f}:"
      fi
    done
    echo
    echo "[三] 徽章长这样："
    printf '  '
    bash "${ROOT}/scripts/statusline-pulse.sh"
    echo
    ;;
esac
```
