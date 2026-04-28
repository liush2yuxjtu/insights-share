```
   __
  <(o )___    呱！我是 Pulse 鸭鸭。
   ( ._> /    你只要会跟 Claude 说话就够了。
    `---'    一个 bash 命令都不用打 🐚🚫
```

# 🦆 鸭鸭专用：跟 Claude 说话装徽章

**前提**：你正坐在一个已经为你打开好的 Claude Code 终端窗口里。
窗口顶上写着 `🦆 鸭鸭沙盒已就位` 之类的横幅，光标停在 Claude 的输入框。

你的全部任务：**打字**。Claude 会替你跑所有命令。

---

## Step 1 · 自检：我在哪个家？

**鸭鸭打字（任选一句）**：

```
我在哪？
```

```
帮我自检一下，我在沙盒还是生产？
```

```
/insights-pulse check
```

**Claude 会回你**：

> 🦆 [SANDBOX]  .sandbox-marker found at /tmp/duck-pulse-sandbox/.sandbox-marker
>    HOME             = /tmp/duck-pulse-sandbox
>    CLAUDE_CONFIG_DIR= /tmp/duck-pulse-sandbox/.claude
>    target settings  = /tmp/duck-pulse-sandbox/.claude/settings.json

**怎么判断**：

| 看到啥 | 含义 | 要做啥 |
|---|---|---|
| 🟢 `🦆 [SANDBOX]` | 沙盒里 | ✅ 放心继续 |
| 🔴 `🚨 [PRODUCTION]` | 真家！ | 🛑 立刻关掉这个窗口，找人确认 |

> 你在这个为你弹开的窗口里，**应该一定看到绿色 SANDBOX**。看到红色就出 bug 了，关掉就行。

---

## Step 2 · 看一眼徽章长啥样（什么都没装的状态）

**鸭鸭打字**：

```
看一下徽章
```

或：

```
/insights-pulse render
```

**Claude 会回你**（灰色一小坨）：

```
🦆 鸭鸭看一眼徽章长啥样：
  [is]
```

意思：插件已加载，但还没数据。这一段是**灰色**的，不要慌。

---

## Step 3 · 装徽章

**鸭鸭打字**：

```
装徽章
```

或：

```
/insights-pulse on
```

**Claude 会回你**：

> 🦆 鸭鸭装徽章（保留你原来的状态栏，把徽章拼到末尾）
> 🦆 [SANDBOX]  …
> {"status":"wired","mode":"postfix","command":"…"}
> [insights-share] statusLine wired (postfix). Backup: …/settings.json.bak
> 下一步：跟 Claude 说「重启 Claude Code」或自己关掉再开，徽章才会出现。

**重点看两件事**：

1. 又看到一次绿色 `🦆 [SANDBOX]` —— **二次确认**没改错地方
2. `wired` —— 装上了

---

## Step 4 · 看徽章总览

**鸭鸭打字**：

```
鸭鸭想看完整状态
```

或：

```
/insights-pulse
```

**Claude 会回你**：

```
🦆 鸭鸭状态总览

[一] 你在哪个家？
  🦆 [SANDBOX]  …

[二] 三个 flag 文件（徽章读这些）：
  pulse-hit:   0
  pulse-sync:  NOCFG|3|0|17xxxxxx
  pulse-pipe:  33|0|17xxxxxx

[三] 徽章长这样：
  [is 0 │ 3· │ 33%cat]
```

颜色应该是**黄色框**（因为 33% 未分类已经触发黄色阈值）。

---

## Step 5 · 试试命中提示

**鸭鸭打字**：

```
我在做 jsonl smoke test，会不会有前人踩过坑？
```

**Claude 会回你**：会插入沙盒里那条 fake "jsonl smoke test 用 mtime 倒序" 心得；同时 hook 把 `pulse-hit` 写成 `1`。

然后再让鸭鸭看徽章：

```
看徽章
```

会看到 `[is 1⚠ │ 3· │ 33%cat]`，**HIT 段变成 `1⚠`**。

---

## Step 6 · 卸下来

**鸭鸭打字**：

```
关徽章
```

或：

```
/insights-pulse off
```

**Claude 会回你**：

> 🦆 鸭鸭卸徽章
> 🦆 [SANDBOX]  uninstalling from …/settings.json
> {"status":"unwired","command":null}

干净退出。

---

## Step 7 · 想退场？

**直接关掉这个 Terminal 窗口就完事**。沙盒在 `/tmp/duck-pulse-sandbox`，重启电脑会自动清。
不会污染你真家的 `~/.claude`，因为整个 Claude 会话都跑在沙盒 HOME 里。

---

## 鸭鸭可以问 Claude 的所有话（速查表）

| 你想干啥 | 用任意一种说法 |
|---|---|
| 自检在哪 | `我在哪？` / `沙盒还是生产？` / `/insights-pulse check` |
| 看徽章 | `看徽章` / `看一眼徽章` / `/insights-pulse render` |
| 看总览 | `鸭鸭状态` / `给我看完整情况` / `/insights-pulse` |
| 装上 | `装徽章` / `把徽章装上` / `/insights-pulse on` |
| 卸掉 | `关徽章` / `卸徽章` / `/insights-pulse off` |
| 重置 flag | `重置一下 flag` / `/insights-pulse reset` |
| 命中前人坑 | 直接自然描述你的任务，比如 `我在做 jsonl ingestion` —— hooks 自动跑 |

---

## ❌ 鸭鸭千万别做的事

- ❌ 不要在 Terminal 直接打 `bash …` 之类的命令 —— 你不需要会 bash
- ❌ 不要试图 `cd` 走出沙盒 —— Claude 会替你处理路径
- ❌ 不要去碰你真家的 `~/.claude` —— 那是另一个 Claude 在用的，跟你这个沙盒 Claude 没关系
- ❌ 看到红色 `🚨 [PRODUCTION]` 不要继续 —— 直接关窗就好

---

```
   __
  <(o )___    呱！沙盒爆了不疼，
   ( ._> /    你只要会打字就够了。
    `---'    
```
