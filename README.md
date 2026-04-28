# insights-share

```
  ╔═══════════════════════════════════════════════════════════╗
  ║  insights-share — Team Claude Code Knowledge Plugin      ║
  ║  前人踩坑，后人不再踩                                    ║
  ╚═══════════════════════════════════════════════════════════╝
```

**LAN 团队共享 Claude Code 心得陷阱 plugin**。静默上传/拉取，让前人的坑成为后人的路标。

## Features

- **静默上传**: 一句话或 Haiku 自动 digest，一键分享给队友
- **静默拉取**: Session 启动时自动从 LAN 队友拉取 index
- **按 prompt 自动推荐**: 用户描述任务时，自动弹出相关陷阱/心得
- **标注来源**: 每条 insight 标注 `uploader @ LAN IP`，追溯可信

## Installation

```bash
# Clone to Claude Code plugins directory
git clone <repo-url> ~/.claude/plugins/insights-share

# Or link from development location
ln -s /path/to/insights-share ~/.claude/plugins/insights-share
```

## Setup

### 1. Configure Teammates

Create `~/.claude-team/config/teammates.json`:

```json
{
  "teammates": [
    { "name": "Alice", "ip": "192.168.1.101" },
    { "name": "Bob", "ip": "192.168.1.102" }
  ]
}
```

### 2. Setup SSH Key-Based Auth

Ensure `~/.ssh/config` allows passwordless rsync to teammate IPs.

### 3. (Optional) Setup Midnight Digest Cron

```bash
# Add to crontab
0 0 * * * bash ~/.claude-team/scripts/haiku-digest.sh
```

Requires `ANTHROPIC_API_KEY` environment variable.

## Usage

### Skills

| Skill | Trigger | Description |
|-------|---------|-------------|
| `/upload-insight` | "记录这个坑"、"share my finding" | 一句话上传 insight |
| `/digest-insights` | "digest my sessions"、"生成今日心得" | Haiku 自动分析 |
| `/sync-insights` | "sync with teammates"、"同步心得" | LAN rsync 同步 |
| `/query-insights` | "X 有什么坑"、"帮我查一下" | 搜索相关 insight |
| `/insights-pulse` | "show pulse"、"心得状态"、"check badge" | 控制 statusline 三段徽章 |

### Hooks

| Event | Action |
|-------|--------|
| `SessionStart` | 静默从 LAN 队友拉取 index；同时刷新 `pulse-sync` 与 `pulse-pipe` flag |
| `UserPromptSubmit` | 自动搜索并推荐相关 insights；同时写 `pulse-hit` flag |

### Agent

`insight-router` agent: 分析用户 prompt，路由到相关 insights，自动推荐。

## Statusline Badge

三段折叠 ANSI 徽章，把 `insights-share` 的实时健康状态摆到状态栏：

```
[is HIT │ VAULT │ PIPE]
   │       │       └── ingest pipeline (uncategorized %, staging backlog)
   │       └────────── LAN sync state (total / peers / since)
   └────────────────── this turn's hit count (recommendations injected)
```

样例：

| Badge | 含义 |
|---|---|
| `[is]` (灰) | 插件已加载但 flag 还没就位，下次 hook 触发后填充 |
| `[is 0 │ 324✓2m │ 12%cat]` (绿) | 一切正常 |
| `[is 3⚠ │ 324✓0m │ 48%cat]` (黄) | 本轮命中 3 条已知坑，pipeline 待分类比例偏高 |
| `[is 7☠ │ ✗sync 2h │ 70%☠]` (红) | 多重红：命中 ≥5、同步失败、超过 60% 未分类 |
| `[is 0 │ 322/2⚠ │ 12%cat]` (黄) | 共享严重单边（322 自己 vs 2 队友） |

### 安装

```bash
# 后缀模式：保留你现有 statusline，把徽章拼到末尾（推荐）
bash scripts/install-statusline.sh

# 独占模式：替换现有 statusline
bash scripts/install-statusline.sh --solo

# 卸载
bash scripts/uninstall-statusline.sh
```

安装器会把 `~/.claude/settings.json` 备份到 `settings.json.bak`，幂等可重入。

### Flag 文件

| 文件 | 写入方 | 格式 |
|---|---|---|
| `~/.claude-team/.pulse-hit`  | `query-insights.sh` (UserPromptSubmit) | 单整数 0–999 |
| `~/.claude-team/.pulse-sync` | `rsync-pull.sh` (SessionStart)         | `STATE\|TOTAL\|PEERS\|TS` |
| `~/.claude-team/.pulse-pipe` | `rsync-pull.sh`、`generate-index.sh`   | `UNCAT_PCT\|STAGING\|TS` |

`scripts/statusline-pulse.sh` 读 flag 时强制：拒绝 symlink、64 字节上限、白名单正则；任何异常都输出空字符串，杜绝注入。

## Data Structure

### Index (`~/.claude-team/insights/index.json`)

```json
[{
  "id": "uuid",
  "name": "Don't mock database in integration tests",
  "uploader": "alice",
  "uploader_ip": "192.168.1.101",
  "when_to_use": "Integration tests with real database",
  "description": "Mocks passed but prod migration failed. Always use real DB for integration tests.",
  "content_hash": "abc123...",
  "raw_hashes": ["raw1", "raw2"],
  "created_at": "2026-04-27T10:00:00Z"
}]
```

### Raw Content (`~/.claude-team/insights/raw/${RAW_HASH}.json`)

```json
{
  "original_message": "用户原始描述...",
  "uploader": "alice",
  "uploader_ip": "192.168.1.101",
  "created_at": "2026-04-27T10:00:00Z"
}
```

## Directory Structure

```
~/.claude-team/
├── config/
│   └── teammates.json      # 队友 IP 配置
├── insights/
│   ├── index.json         # 主索引
│   ├── index-hourly/      # 每小时快照
│   └── raw/               # 原始内容
└── cache/
    ├── peer-indexes/      # 队友 index 缓存
    └── query_cache.json   # 查询缓存
```

## API

### query-insights.sh

```bash
# 手动查询
~/.claude-team/scripts/query-insights.sh "Python asyncio"

# 清空查询缓存
rm ~/.claude-team/cache/query_cache.json
```

### rsync-pull.sh / rsync-push.sh

```bash
# 手动拉取队友 insights
~/.claude-team/scripts/rsync-pull.sh

# 手动推送本地 insights
~/.claude-team/scripts/rsync-push.sh
```

## Requirements

- `jq`
- `rsync` with SSH key-based auth to teammates
- `curl` (for Haiku digest)
- `ANTHROPIC_API_KEY` (for Haiku digest)

## License

MIT
