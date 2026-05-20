---
name: hermes-memory-browser
description: Browse, search, edit, and manage Hermes agent memories — a web UI for facts, entities, sessions, and skills with bulk operations, dark mode, and Markdown rendering.
version: 1.0.0
author: ikun
license: MIT
---

# 🧠 Hermes Memory Browser

可视化浏览 Hermes Agent 的记忆系统，管理事实、实体、对话历史和技能文件。

## 功能

- **📝 事实管理** — 浏览、搜索、编辑、删除 Hermes 记忆事实，支持 FTS5 全文搜索
- **🏷️ 实体浏览** — 查看所有记忆实体及其关联事实
- **💬 对话浏览** — 按时间查看历史对话，支持全文搜索
- **🔧 技能阅读** — 浏览已安装技能文档，展开查看关联文件
- **📊 统计面板** — 事实总数、实体数、平均信任度、对话数
- **🌙 深色模式** — 支持切换深色/浅色主题
- **📤 导入/导出** — JSON 备份和恢复
- **⌨️ 键盘快捷键** — `/`搜索 `N`新增 `J/K`选中 `A`全选 `Del`删除 `R`恢复 `Esc`关闭

## 快速开始

```bash
# 启动（默认端口 8643）
python3 server.py

# 指定端口
python3 server.py 8080
```

浏览器打开 `http://127.0.0.1:8643`

## 文件结构

```
hermes-memory-browser/
├── SKILL.md          # 本文件
├── server.py         # FastAPI 后端 + 前端（单文件）
└── scripts/
    └── start.sh      # 一键启动脚本
```

## 依赖

- Python 3.8+
- `fastapi` + `uvicorn`（pip install fastapi uvicorn）

## 安装

```bash
# 方式 1：作为 Hermes 技能安装
hermes skill install <仓库地址>

# 方式 2：手动克隆
git clone <仓库地址> ~/.hermes/skills/devops/hermes-memory-browser
cd ~/.hermes/skills/devops/hermes-memory-browser
python3 server.py

# 方式 3：作为 systemd 用户服务自动启动
cp templates/hermes-memory-web.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-memory-web
```

## API 端点

| 路径 | 说明 |
|:-----|:-----|
| `GET /` | 前端页面 |
| `GET /api/stats` | 统计概览 |
| `GET /api/facts` | 事实列表（支持搜索/筛选/分页） |
| `GET /api/facts/{id}` | 事实详情 |
| `POST /api/facts/new` | 新增事实 |
| `POST /api/facts/{id}/edit` | 编辑事实 |
| `DELETE /api/facts/{id}` | 删除事实（软/硬） |
| `POST /api/facts/bulk` | 批量操作 |
| `GET /api/facts/export` | 导出所有事实 |
| `POST /api/facts/import` | 导入事实 |
| `GET /api/entities` | 实体列表 |
| `GET /api/entities/{id}` | 实体详情（含关联事实） |
| `GET /api/sessions` | 对话列表 |
| `GET /api/sessions/{id}` | 对话详情（含消息） |
| `GET /api/skills` | 技能列表 |
| `GET /api/skills/{name}` | 技能详情（含关联文件） |
| `GET /api/skills/{name}/file` | 技能关联文件内容 |
| `GET /api/tags` | 所有标签列表 |
| `GET /api/tasks` | 当前任务列表 |

## 数据来源

- **memory_store.db** — `~/.hermes/memory_store.db`（Hermes 持久化记忆数据库）
- **state.db** — `~/.hermes/state.db`（对话记录和任务状态）
- **SKILL.md** — `~/.hermes/skills/`（技能文档目录）
