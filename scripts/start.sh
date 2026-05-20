#!/usr/bin/env bash
# Hermes Memory Browser — 一键启动脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_PY="$SKILL_DIR/server.py"
PORT="${1:-8643}"

if [ ! -f "$SERVER_PY" ]; then
    echo "❌ 未找到 server.py，请确认 skill 安装正确"
    exit 1
fi

# 尝试 hermes-agent venv（含 fastapi），回退到系统 python
if [ -f "$HOME/.hermes/hermes-agent/venv/bin/python3" ]; then
    PYTHON="$HOME/.hermes/hermes-agent/venv/bin/python3"
else
    PYTHON="python3"
fi

echo "🧠 Hermes Memory Browser starting on http://127.0.0.1:$PORT"
echo "   Python: $PYTHON"
echo "   Press Ctrl+C to stop"

exec "$PYTHON" "$SERVER_PY" "$PORT"
