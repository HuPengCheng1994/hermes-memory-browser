<p align="center">
  <img src="https://img.shields.io/badge/Hermes-Memory%20Browser-2563eb?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI4MCIgaGVpZ2h0PSI4MCIgdmlld0JveD0iMCAwIDgwIDgwIj48dGV4dCB5PSIuOWVtIiBmb250LXNpemU9IjcwIj7wn6eGPC90ZXh0Pjwvc3ZnPg==">
  <img src="https://img.shields.io/github/license/HuPengCheng1994/hermes-memory-browser?style=flat-square">
  <img src="https://img.shields.io/badge/python-3.8+-blue?style=flat-square">
  <img src="https://img.shields.io/badge/FastAPI-%2300C7B7?style=flat-square&logo=fastapi">
</p>

# 🧠 Hermes Memory Browser

> Browse, search, edit, and manage Hermes Agent memories — a web UI for facts, entities, sessions, and skills.

A single-file FastAPI web application that opens a window into your Hermes agent's memory system. No build step, no npm, no database setup — just `python3 server.py` and open a browser.

> **Screenshot**: Open `http://127.0.0.1:8643` in your browser to see the UI. This screenshot was taken from a real session — [click here](https://github.com/HuPengCheng1994/hermes-memory-browser) for a live view.

## ✨ Features

| | |
|---|---|
| **📝 Fact Management** | Browse, search (FTS5), edit, and delete memory facts with full-text search across CJK languages |
| **🏷️ Entity Browser** | View all extracted entities and their associated facts |
| **💬 Session History** | Browse past conversations with search, Markdown rendering, and message filtering |
| **🔧 Skill Reader** | Read installed skill documentation inline, expand linked files |
| **📊 Stats Dashboard** | Fact count, entity count, average trust score, session count at a glance |
| **🌙 Dark Mode** | Toggle between light and dark themes (persisted in localStorage) |
| **⌨️ Keyboard Shortcuts** | `/` search · `N` new fact · `J/K` navigate · `A` select all · `Del` delete · `R` restore · `Esc` close |
| **📤 Import/Export** | Full JSON backup and restore of facts with entity associations |
| **📱 Responsive** | Works on desktop and mobile |

## 🚀 Quick Start

```bash
# 1. Install dependencies
pip install fastapi uvicorn

# 2. Start the server
python3 server.py

# 3. Open browser
#    http://127.0.0.1:8643
```

The server reads your existing Hermes memory database (`~/.hermes/memory_store.db`) and session store (`~/.hermes/state.db`) — no configuration needed.

### Custom Port

```bash
python3 server.py 8080
```

### As a Service (systemd)

```bash
cp templates/hermes-memory-web.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-memory-web
```

## 📦 As a Hermes Skill

```bash
hermes skill install https://github.com/HuPengCheng1994/hermes-memory-browser
```

Then start from the skill directory:

```bash
cd ~/.hermes/skills/devops/hermes-memory-browser
python3 server.py
```

## 🗺️ File Structure

```
hermes-memory-browser/
├── SKILL.md                    # Hermes skill documentation
├── README.md                   # This file
├── server.py                   # FastAPI backend + frontend (single file, ~2700 LOC)
├── scripts/
│   └── start.sh               # Convenience launcher
└── templates/
    └── hermes-memory-web.service  # systemd user service template
```

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
