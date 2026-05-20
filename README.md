<p align="center">
  <img src="https://img.shields.io/badge/Hermes-Memory%20Browser-2563eb?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI4MCIgaGVpZ2h0PSI4MCIgdmlld0JveD0iMCAwIDgwIDgwIj48dGV4dCB5PSIuOWVtIiBmb250LXNpemU9IjcwIj7wn6eGPC90ZXh0Pjwvc3ZnPg==">
  <img src="https://img.shields.io/github/license/HuPengCheng1994/hermes-memory-browser?style=flat-square">
  <img src="https://img.shields.io/badge/python-3.8+-blue?style=flat-square">
  <img src="https://img.shields.io/badge/FastAPI-%2300C7B7?style=flat-square&logo=fastapi">
</p>

# 🧠 Hermes Memory Browser

> 浏览、搜索、编辑和管理 Hermes Agent 记忆系统 —— 事实、实体、对话、技能一站式 Web UI。

单文件 FastAPI 应用，无需构建步骤、npm、数据库配置，`python3 server.py` 即可运行。

---

# 中文说明 🇨🇳

## ✨ 功能

| | | |
|---|---|---|
| **📝 事实管理** | 浏览、搜索（FTS5 全文检索，支持中日韩）、编辑、删除记忆事实 |
| **🏷️ 实体浏览** | 查看所有提取的实体及其关联事实 |
| **💬 对话历史** | 浏览历史对话，支持搜索、Markdown 渲染、消息过滤 |
| **🔧 技能阅读** | 在线查看已安装的技能文档，展开关联文件 |
| **📊 统计面板** | 事实数、实体数、平均信任度、对话数一目了然 |
| **🌙 深色模式** | 明暗主题切换（自动保存到 localStorage） |
| **🌐 中/英切换** | 一键切换界面语言（自动保存） |
| **⌨️ 快捷键** | `/` 搜索 · `N` 新增 · `J/K` 选中 · `A` 全选 · `Del` 删除 · `R` 恢复 · `Esc` 关闭 |
| **📤 导入/导出** | 完整 JSON 备份和恢复（含实体关联） |
| **📱 响应式** | 桌面端和移动端均可使用 |

## 🚀 快速启动

```bash
# 1. 安装依赖
pip install fastapi uvicorn

# 2. 启动服务
python3 server.py

# 3. 浏览器打开
#    http://127.0.0.1:8643
```

服务会自动读取已有的 Hermes 记忆数据库（`~/.hermes/memory_store.db`）和会话存储（`~/.hermes/state.db`），无需任何配置。

### 自定义端口

```bash
python3 server.py 8080
```

### 作为系统服务（systemd）

```bash
cp templates/hermes-memory-web.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-memory-web
```

## 📦 作为 Hermes Skill 安装

```bash
hermes skill install https://github.com/HuPengCheng1994/hermes-memory-browser
```

然后在 skill 目录启动：

```bash
cd ~/.hermes/skills/devops/hermes-memory-browser
python3 server.py
```

## 🗺️ 文件结构

```
hermes-memory-browser/
├── SKILL.md                    # Hermes skill 文档
├── README.md                   # 本文件
├── server.py                   # FastAPI 后端 + 前端（单文件，~2900 行）
├── assets/
│   └── screenshot.png          # 界面截图
├── scripts/
│   └── start.sh               # 启动脚本
└── templates/
    └── hermes-memory-web.service  # systemd 服务模板
```

---

# English 🇬🇧

## ✨ Features

| | | |
|---|---|---|
| **📝 Fact Management** | Browse, search (FTS5, CJK support), edit, and delete memory facts |
| **🏷️ Entity Browser** | View extracted entities and their associated facts |
| **💬 Session History** | Browse past conversations with search, Markdown rendering, message filtering |
| **🔧 Skill Reader** | Read installed skill docs inline, expand linked files |
| **📊 Stats Dashboard** | Fact count, entity count, avg trust score, session count at a glance |
| **🌙 Dark Mode** | Toggle light/dark themes (persisted in localStorage) |
| **🌐 Language Switch** | One-click Chinese / English toggle (persisted) |
| **⌨️ Keyboard Shortcuts** | `/` search · `N` new fact · `J/K` navigate · `A` select all · `Del` delete · `R` restore · `Esc` close |
| **📤 Import/Export** | Full JSON backup and restore of facts with entity associations |
| **📱 Responsive** | Works on desktop and mobile |

## 🚀 Quick Start

```bash
pip install fastapi uvicorn
python3 server.py
# open http://127.0.0.1:8643
```

The server reads your existing Hermes memory database (`~/.hermes/memory_store.db`) and session store (`~/.hermes/state.db`) — zero config.

### Custom Port

```bash
python3 server.py 8080
```

### As a systemd Service

```bash
cp templates/hermes-memory-web.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-memory-web
```

## 📦 As a Hermes Skill

```bash
hermes skill install https://github.com/HuPengCheng1994/hermes-memory-browser
cd ~/.hermes/skills/devops/hermes-memory-browser
python3 server.py
```

---

## 🔌 API Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/` | Frontend HTML page |
| `GET` | `/api/stats` | Dashboard statistics |
| `GET` | `/api/facts` | List facts (search, filter, paginate) |
| `POST` | `/api/facts/new` | Create a fact |
| `GET/POST/DELETE` | `/api/facts/{id}` | Read, edit, soft-delete a fact |
| `POST` | `/api/facts/bulk` | Batch operations (delete/restore/tag) |
| `GET` | `/api/facts/export` | Export all facts as JSON |
| `POST` | `/api/facts/import` | Import facts from JSON |
| `GET` | `/api/entities` | List entities |
| `GET` | `/api/entities/{id}` | Entity detail with associated facts |
| `GET` | `/api/sessions` | List conversations |
| `GET` | `/api/sessions/{id}` | Session messages |
| `GET` | `/api/skills` | List installed skills |
| `GET` | `/api/skills/{name}` | Skill detail with linked files |
| `GET` | `/api/tags` | All unique tags |
| `GET` | `/api/tasks` | Current task list |

Full documentation in [SKILL.md](SKILL.md).

## 🧪 Tech Stack

- **Backend:** FastAPI + uvicorn
- **Database:** SQLite3 (built-in `holographic` memory provider)
- **Search:** SQLite FTS5 with CJK tokenization
- **Frontend:** Vanilla HTML/CSS/JS + [marked.js](https://marked.js.org/) for Markdown
- **Dependencies:** `fastapi`, `uvicorn` — that's it

## 🤝 Contributing

PRs welcome! This is a single-file app by design — keep it that way. If you find a bug or want a feature, open an issue.

## 📄 License

MIT — do whatever you want.
