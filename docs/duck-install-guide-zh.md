```
   __
  <(o )___
   ( ._> /     呱呱！我是 Pulse 小鸭子
    `---'      帮你装一条会发光的状态栏徽章
```

# 🦆 鸭鸭专用：insights-share Statusline Pulse 安装指南

只读这一页就能装好。每一步都告诉你**会改什么**、**怎么撤回**、**怎么自检自己有没有走丢到生产环境**。

## 0. 先做一件事：自检你在哪个屋子

打开终端，跑：

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh --check
```

会看到两种横幅之一：

| 横幅 | 含义 | 安全度 |
|---|---|---|
| 🟢 `🦆 [SANDBOX]` | 你在沙盒里，怎么折腾都不影响真 `~/.claude` | ✅ 放心玩 |
| 🔴 `🚨 [PRODUCTION]` | 这是你日常用的 `~/.claude`！ | ⚠️ 默认会拒绝写入，逼你确认 |

**如果你想先在沙盒里试，请确认你看到的是绿色 `🦆 [SANDBOX]`。**
若不是，跳到第 1 步把沙盒拉起来。

---

## 1. 拉沙盒（一行命令）

```bash
source $INSIGHTS_PLUGIN_DIR/scripts/sandbox-bootstrap.sh
```

这会做四件事：

1. 在 `/tmp/duck-pulse-sandbox/` 起一个全新假家
2. 放一个 `.sandbox-marker` 文件，让安装脚本认出这是沙盒
3. 写一个迷你 fake `index.json`（3 条 insight，含一条 `uncategorized`）
4. **export** 三个环境变量到你当前 shell：
   - `HOME=/tmp/duck-pulse-sandbox`
   - `CLAUDE_CONFIG_DIR=/tmp/duck-pulse-sandbox/.claude`
   - `INSIGHTS_PLUGIN_DIR=…/insights-share`

> ❗ 必须用 `source`，不能 `bash`。`bash` 起一个新进程，env 不会带回到你这里。

**自检：再跑一次 `--check`**

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh --check
```

看到 🟢 `🦆 [SANDBOX]` 和路径都指向 `/tmp/duck-pulse-sandbox/...`，就对了。

---

## 2. 装徽章（默认 postfix，最稳）

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh
```

发生了什么：

- 备份：`$CLAUDE_CONFIG_DIR/settings.json` → `settings.json.bak`
- 修改：把现有 `statusLine.command` 拼到我们的 pulse 命令前，用 `;` 分隔
- 标记：在命令里加注释 `# insights-share-pulse`，方便日后识别和卸载

**两种安装模式**：

```bash
# 后缀（推荐，保留原 statusline）
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh

# 独占（替换原 statusline，只剩 pulse 徽章）
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh --solo
```

---

## 3. 让徽章拿到数据（喂三个 flag 文件）

徽章读 `~/.claude-team/.pulse-{hit,sync,pipe}` 三个 flag。在沙盒里，自己跑一次插件原本的 hook 脚本就能填进去：

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/rsync-pull.sh                     # 写 .pulse-sync + .pulse-pipe
bash $INSIGHTS_PLUGIN_DIR/scripts/query-insights.sh "jsonl"  # 写 .pulse-hit（命中 fake 索引里的 1 条）
```

> ℹ️ 沙盒里没有真的队友 IP，所以 `rsync-pull.sh` 会写入 `STATE=NOCFG`（没配置）；vault 段会显示灰色而不是绿色，这正常。

**看一眼三个 flag**：

```bash
for f in pulse-hit pulse-sync pulse-pipe; do
  printf '  %-12s %s\n' "$f:" "$(cat $HOME/.claude-team/.$f 2>/dev/null || echo '(missing)')"
done
```

---

## 4. 渲染徽章

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/statusline-pulse.sh; echo
```

应该看到类似（黄色框）：

```
[is 1⚠ │ 3· │ 33%cat]
```

意思：本轮命中 1 条已知坑（黄色 ⚠）/ vault 3 条无队友配置（灰色 ·）/ pipeline 33% 未分类（黄色）。
整体框是黄色，因为有任意一段告警就会让整个徽章变黄。

---

## 5. 启动 Claude 实测

```bash
claude -p \
  --plugin-dir "$INSIGHTS_PLUGIN_DIR" \
  --output-format stream-json --verbose \
  --include-hook-events \
  "我在做 jsonl ingestion，想看前人踩过的坑"
```

> 注意：用 `claude -p` 会真的跑模型、扣 token。只想看插件加载情况、不烧钱，加 `--bare`：模型调用会失败（"Not logged in"），但 init JSON 会列出所有 plugin 和 slash command，证明插件被发现了。

`--include-hook-events` 会在 stream-json 里给你看 SessionStart / UserPromptSubmit hook 触发的全过程。跑完再看 flag 文件 mtime，应该都被刷新了。

---

## 6. 用插件自带的 slash command 看状态

在 Claude REPL 里直接打：

```
/insights-pulse status
```

会输出：

```
insights-pulse — current state
  pulse-hit:   1
  pulse-sync:  NOCFG|3|0|1745812345
  pulse-pipe:  33|0|1745812345
  badge:       [is 1⚠ │ 3· │ 33%cat]
```

其它子命令：

| 命令 | 行为 |
|---|---|
| `/insights-pulse status` | 默认，打印 flag + 渲染 |
| `/insights-pulse on` | 跑 install-statusline.sh（postfix 模式） |
| `/insights-pulse solo` | 跑 install-statusline.sh --solo |
| `/insights-pulse off` | 跑 uninstall-statusline.sh |
| `/insights-pulse reset` | 删除三个 flag，下次 hook 触发后重建 |
| `/insights-pulse render` | 只渲染一下，不打印 flag 详情 |

---

## 7. 卸载（沙盒和真环境都一样）

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/uninstall-statusline.sh
```

它做的事：

1. 备份 `settings.json` → `settings.json.bak`
2. 把 `# insights-share-pulse` 标记的那段命令从 `statusLine.command` 里拆掉
3. 如果拆完命令为空，整个 `statusLine` 字段也删掉，让 Claude Code 回到默认行为

---

## 8. 离开沙盒，回到你的真家

`source` 进来的环境变量只属于当前 shell。**直接关掉这个终端窗口**，下次新开终端就回到真家了。

或者手动 unset：

```bash
unset HOME CLAUDE_CONFIG_DIR INSIGHTS_PLUGIN_DIR
exec $SHELL -l   # 重新加载登录 shell
```

---

## 9. 想真的装到生产 ~/.claude 怎么办？

**先看清楚你在哪儿**：

```bash
echo "HOME=$HOME"
echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-(not set)}"
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh --check
```

确认是 🚨 `[PRODUCTION]` 且路径是你的真家后，加保险栓 `--allow-production`：

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/install-statusline.sh --allow-production
```

> 默认拒绝是为了**保护你不小心把测试代码塞进真 settings.json**。每次必须显式说 "我知道我在改生产，让我过"。

卸载同理：

```bash
bash $INSIGHTS_PLUGIN_DIR/scripts/uninstall-statusline.sh --allow-production
```

---

## 10. 出问题了怎么办？

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 徽章是空的 | 三个 flag 文件都不存在或都是 symlink | 手动跑一次 `rsync-pull.sh` 和 `query-insights.sh` 喂数据 |
| 徽章是 `[is]` 灰色 | flag 全 0 / 缺失，但脚本载入正常 | 这是「健康但还没活动」的提示，不是 bug |
| 颜色全错 | 终端不支持 256-color | iTerm2 / Ghostty / VS Code Terminal 都支持，老 macOS Terminal 可能要切配色 |
| `[PRODUCTION]` 红色挡住了我 | 安装器在保护你 | 先 `source sandbox-bootstrap.sh` 进沙盒，或者主动加 `--allow-production` |
| `claude -p` 报 `Not logged in` | 你加了 `--bare` | 拿掉 `--bare` 即可（会真的烧 token） |

---

```
   __
  <(o )___    呱！沙盒爆了不疼，
   ( ._> /    生产爆了真疼，
    `---'    所以我才一定要让你看清自己在哪 🦆
```
