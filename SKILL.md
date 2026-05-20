---
name: hermes-memory-browser
description: Browse, search, edit, and manage Hermes agent memories — a web UI for facts, entities, sessions, and skills with bulk operations, dark mode, and Markdown rendering.
version: 1.1.0
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
- **🌐 中英文切换** — 右上角 🇨🇳/🇬🇧 按钮，实时切换，刷新保持
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

## 启动重要提示

- **需要 hermes-agent 的 venv**：系统 python 可能没有 `fastapi`，必须用：
  ```bash
  ~/.hermes/hermes-agent/venv/bin/python3 server.py
  # 或者先 source 再跑
  source ~/.hermes/hermes-agent/venv/bin/activate && python3 server.py
  ```
- **端口冲突**：如果有旧版 `memory_api.py` 占着端口，先 kill：
  ```bash
  lsof -ti:8643 | xargs kill -9
  ```
- **端口参数**：`python3 server.py 8080` 可指定任意端口

## 依赖

- Python 3.8+
- `fastapi` + `uvicorn`（已安装在 hermes-agent venv 中）

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

## i18n 架构

前端实现了完整的中英文切换功能，架构为"字典 + 切换按钮 + applyLang 函数"三件套。

### 核心代码位置（server.py 内）

```
<script>
// ===== i18n =====
let _LANG = (() => { ... })();        // 从 localStorage 读取语言偏好
const _L = { zh: {...}, en: {...} };  // 中英文字典
function __(key, fallback) { ... }    // 翻译函数
function applyLang() { ... }          // 应用到静态 HTML
function toggleLang() { ... }         // 切换语言入口
</script>
```

### 命名规范

- **字典 key**：蛇形命名（如 `add_fact`, `search_facts`, `toggle_theme`）
- **HTML 属性**：
  - `data-i18n="key"` — 替换 `textContent`
  - `data-i18n-placeholder="key"` — 替换 `placeholder`
  - `data-i18n-title="key"` — 替换 `title`
- **动态渲染**：JS 渲染模板中用 `__(key)` 或 `__('key')`

### 重要陷阱

1. **`_LANG` 必须用 `let` 不能用 `const`**，否则 `toggleLang()` 无法重新赋值
2. **`<select>` 的 `<option>` 不能加 data-i18n 属性**（option 不支持自定义属性），需在 `applyLang()` 里用 `opts` 映射手动遍历替换
3. **数据-i18n 只替换 textContent**，如果元素里还有子节点（如 `<h1><small>`），data-i18n 会覆盖掉子节点。目前 h1 的 `<small>` 放 emoji 后面直接作为 h1 文本的一部分处理
4. **记得添加中文 placeholder 作为默认值**，JS 未加载前用户看到的是中文，不突兀

### 动态生成的 DOM 也要做 i18n

对于 JS 运行时创建的动态元素（如下方键盘提示横幅），需要三步：

1. 将硬编码中文替换为 `__(key)` 模板字面量
2. 创建一个独立的 `updateXxx()` 函数（如 `updateKbdHint()`）
3. 在 `toggleLang()` 末尾调用该函数刷新

```js
// 页面加载时调用一次
updateKbdHint();

function toggleLang() {
  _LANG = _LANG === 'zh' ? 'en' : 'zh';
  try { localStorage.setItem('mb-lang', _LANG); } catch(e) {}
  applyLang();
  updateKbdHint();  // ← 动态元素也必须刷新
  // ... 继续 re-render 当前 tab
}
```

### 切换按钮样式

- **不要复用 `.theme-toggle`（36px 正圆）作为语言切换按钮**——"🇨🇳/🇬🇧"是双 emoji，圆形容不下
- 正确的做法：单独建一个 `.lang-toggle` 类，用 8px 圆角（跟 `.btn` 统一）、水平 padding、flex 布局
- 如果按钮只有简单图标（如 🌙），用圆形 `.theme-toggle`；如果有文字或多 emoji，用矩形 `.btn` 或自定义 `.lang-toggle`

```css
.lang-toggle {
  padding: 0 12px; height: 36px; border-radius: 8px;
  ...
}
```

## 数据来源

- **memory_store.db** — `~/.hermes/memory_store.db`（Hermes 持久化记忆数据库）
- **state.db** — `~/.hermes/state.db`（对话记录和任务状态）
- **SKILL.md** — `~/.hermes/skills/`（技能文档目录）
