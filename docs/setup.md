# 使用前配置 / Setup Guide

```
  ╔═══════════════════════════════════════════════════════════╗
  ║  insights-share 使用前配置                               ║
  ║  Setup Before First Use                                  ║
  ╚═══════════════════════════════════════════════════════════╝
```

## 第一步：安装 Plugin

```bash
# 方式 1：Link 开发目录
ln -s /Users/m1/projects/V3p1meta-harness/insights-share ~/.claude/plugins/insights-share

# 方式 2：复制到 plugins 目录
cp -r /Users/m1/projects/V3p1meta-harness/insights-share ~/.claude/plugins/
```

验证安装成功：
```bash
claude --help | grep insights
# 应该看到 upload-insight, digest-insights, sync-insights, query-insights
```

---

## 第二步：创建本地数据目录

```bash
mkdir -p ~/.claude-team/{config,insights/{raw,index-hourly},cache/peer-indexes}
```

---

## 第三步：配置队友 IP

```bash
# 复制示例配置
cp insights-share/config/teammates.example.json ~/.claude-team/config/teammates.json

# 编辑（填入真实 IP 和名字）
nano ~/.claude-team/config/teammates.json
```

`teammates.json` 格式：
```json
{
  "teammates": [
    { "name": "Alice", "ip": "192.168.1.101", "username": "alice" },
    { "name": "Bob", "ip": "192.168.1.102", "username": "bob" },
    { "name": "Charlie", "ip": "192.168.1.103", "username": "charlie" }
  ]
}
```

**注意**：`username` 字段指定 SSH 连接时使用的远程用户名。如果省略，默认为本地用户名 `m1`。

**注意**：IP 必须是 LAN 内可达的固定 IP。

---

## 第四步：配置 SSH Key-Based Rsync

确保能无密码 SSH 到队友机器：

```bash
# 生成本机 SSH 公钥（如果没有）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 复制到每台队友机器
ssh-copy-id teammate@192.168.1.101
ssh-copy-id teammate@192.168.1.102
ssh-copy-id teammate@192.168.1.103
```

验证：
```bash
# 应该能无密码 SSH
ssh teammate@192.168.1.101 "echo ok"
```

---

## 第五步：(可选) 设置午夜自动 Digest

用 Haiku 自动分析过去一天的 session logs：

```bash
# 添加到 crontab
(crontab -l 2>/dev/null; echo "0 0 * * * bash ~/.claude-team/scripts/haiku-digest.sh") | crontab -
```

确保环境变量有 `ANTHROPIC_API_KEY`：
```bash
# 加到 ~/.profile 或 ~/.bashrc
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.profile
source ~/.profile
```

---

## 第六步：初始化本地 Index

```bash
# 创建空 index
echo "[]" > ~/.claude-team/insights/index.json

# 验证
cat ~/.claude-team/insights/index.json
# 应该输出：[]
```

---

## 验证完整流程

```bash
# 1. 测试上传 skill
claude
# > /upload-insight
# > 我在用 Claude Code 写 Python 时发现，不要在 tests 里 import production code，会导致循环依赖

# 2. 查看 index
cat ~/.claude-team/insights/index.json | jq .

# 3. 测试查询
# > /query-insights Python

# 4. 测试同步（需要至少 2 台机器）
# > /sync-insights
```

---

## 目录结构总览

```
~/.claude-team/
├── config/
│   └── teammates.json      # ← 你需要编辑这个
├── insights/
│   ├── index.json         # ← 主索引，会自动创建
│   ├── index-hourly/      # ← 每小时快照
│   └── raw/               # ← 原始内容
└── cache/
    ├── peer-indexes/      # ← 队友 index 缓存
    └── query_cache.json   # ← 查询缓存
```

---

## 常见问题

| 问题 | 解决方案 |
|------|----------|
| `rsync: connection unexpectedly closed` | 检查 SSH key 配置和队友机器是否在线 |
| `jq: command not found` | `brew install jq` 或 `apt install jq` |
| `ANTHROPIC_API_KEY` 报错 | 确认环境变量已设置 `echo $ANTHROPIC_API_KEY` |
| SessionStart 没有拉取 | 检查 `~/.claude/plugins/insights-share/hooks/hooks.json` 是否存在 |
