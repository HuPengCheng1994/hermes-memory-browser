#!/usr/bin/env python3
"""
Hermes 记忆系统 Web API
从 memory_store.db 提供 REST 接口
"""
import sqlite3
import json
import os
import asyncio
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, Query, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request as StarletteRequest
import re
import logging

MAX_BODY_SIZE = 1_000_000  # 1MB

def cjk_tokenize(text: str) -> str:
    """在中文/日文/韩文CJK字符间插入空格，让FTS5可逐字搜索。"""
    if not text:
        return ""
    # 在CJK字符前后加空格，然后在CJK和非CJK交界处也加空格
    text = re.sub(r'([\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff\uac00-\ud7af])', r' \1 ', text)
    # 规范化多重空格
    return re.sub(r'\s+', ' ', text).strip()

class BodyLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: StarletteRequest, call_next):
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > MAX_BODY_SIZE:
            from fastapi.responses import JSONResponse as JR
            return JR({"error": f"Request body too large (max {MAX_BODY_SIZE} bytes)"}, status_code=413)
        return await call_next(request)

import uvicorn

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("memory_web")

DB_PATH = os.path.expanduser("~/.hermes/memory_store.db")
SESSION_DB = os.path.expanduser("~/.hermes/state.db")
SESSIONS_DIR = os.path.expanduser("~/.hermes/sessions/")

app = FastAPI(title="Hermes Memory Browser", version="1.0.1")
app.add_middleware(CORSMiddleware, allow_origins=["http://127.0.0.1:8643", "http://localhost:8643"], allow_methods=["GET", "POST", "DELETE", "OPTIONS"], allow_headers=["Content-Type", "Accept"])
app.add_middleware(BodyLimitMiddleware)

def ensure_schema():
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        cols = conn.execute("PRAGMA table_info(facts)").fetchall()
        names = {c[1] for c in cols}
        if "deleted_at" not in names:
            conn.execute("ALTER TABLE facts ADD COLUMN deleted_at TEXT")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_facts_deleted_at ON facts(deleted_at)")
        # 重建 FTS 索引——确保 CJK 字符被正确分詞
        need_rebuild = conn.execute(
            "SELECT COUNT(*) FROM facts_fts WHERE content GLOB '*[\u4e00-\u9fff]*' AND content NOT GLOB '* *'"
        ).fetchone()[0]
        if need_rebuild > 0:
            all_ids = conn.execute("SELECT fact_id FROM facts").fetchall()
            for (fid,) in all_ids:
                fts_remove_fact(conn, fid, "", "")
                row = conn.execute("SELECT content, tags FROM facts WHERE fact_id = ?", [fid]).fetchone()
                if row:
                    conn.execute(
                        "INSERT INTO facts_fts(rowid, content, tags) VALUES (?, ?, ?)",
                        [fid, cjk_tokenize(row[0]), cjk_tokenize(row[1] or "")],
                    )
        conn.commit()
    finally:
        conn.close()

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_session_db():
    conn = sqlite3.connect(SESSION_DB)
    conn.row_factory = sqlite3.Row
    return conn

def fts_remove_fact(conn, fact_id: int, content: str, tags: str):
    conn.execute(
        "INSERT INTO facts_fts(facts_fts, rowid, content, tags) VALUES ('delete', ?, ?, ?)",
        [fact_id, content or "", tags or ""],
    )

def fts_upsert_fact(conn, fact_id: int):
    row = conn.execute("SELECT content, tags FROM facts WHERE fact_id = ?", [fact_id]).fetchone()
    if not row:
        return
    fts_remove_fact(conn, fact_id, row["content"], row["tags"] or "")
    conn.execute(
        "INSERT INTO facts_fts(rowid, content, tags) VALUES (?, ?, ?)",
        [fact_id, cjk_tokenize(row["content"]), cjk_tokenize(row["tags"] or "")],
    )

ensure_schema()

# ─── Facts API ───

@app.post("/api/facts/{fact_id}/edit")
def edit_fact(fact_id: int, data: dict):
    conn = get_db()
    try:
        fact = conn.execute("SELECT fact_id, content, category, tags, trust_score FROM facts WHERE fact_id = ? AND deleted_at IS NULL", [fact_id]).fetchone()
        if not fact:
            raise HTTPException(404, "Fact not found")
        updates = []
        params = []
        for field in ["content", "category", "tags", "trust_score"]:
            if field in data and data[field] is not None:
                updates.append(f"{field} = ?")
                params.append(data[field])
        if updates:
            params.append(fact_id)
            conn.execute(f"UPDATE facts SET {', '.join(updates)}, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?", params)
            # Re-index FTS
            fts_upsert_fact(conn, fact_id)
            conn.commit()
        return {"ok": True}
    finally:
        conn.close()

@app.delete("/api/facts/{fact_id}")
def delete_fact(fact_id: int, hard: int = Query(0)):
    conn = get_db()
    try:
        fact = conn.execute("SELECT fact_id, content, tags, deleted_at FROM facts WHERE fact_id = ?", [fact_id]).fetchone()
        if not fact:
            raise HTTPException(404, "Fact not found")
        if int(hard) == 1:
            fts_remove_fact(conn, fact_id, fact["content"], fact["tags"] or "")
            conn.execute("DELETE FROM fact_entities WHERE fact_id = ?", [fact_id])
            conn.execute("DELETE FROM facts WHERE fact_id = ?", [fact_id])
            conn.commit()
            return {"ok": True, "deleted_id": fact_id, "hard": True}

        if fact["deleted_at"]:
            return {"ok": True, "deleted_id": fact_id, "already_deleted": True}
        fts_remove_fact(conn, fact_id, fact["content"], fact["tags"] or "")
        conn.execute("UPDATE facts SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?", [fact_id])
        conn.commit()
        return {"ok": True, "deleted_id": fact_id, "hard": False}
    finally:
        conn.close()

@app.post("/api/facts/new")
def create_fact(data: dict):
    conn = get_db()
    try:
        content = data.get("content", "").strip()
        if not content:
            raise HTTPException(400, "内容不能为空")
        category = data.get("category", "general")
        tags = data.get("tags", "")
        try:
            raw_ts = data.get("trust_score", 0.5)
            trust_score = min(max(float(raw_ts) if raw_ts is not None else 0.5, 0.0), 1.0)
        except (ValueError, TypeError):
            raise HTTPException(400, "trust_score 必须是数字")
        cursor = conn.execute(
            "INSERT INTO facts (content, category, tags, trust_score) VALUES (?, ?, ?, ?)",
            [content, category, tags, trust_score],
        )
        new_id = cursor.lastrowid
        fts_upsert_fact(conn, new_id)
        conn.commit()
        return {"ok": True, "fact_id": new_id}
    except sqlite3.IntegrityError:
        raise HTTPException(409, "该内容已存在")
    finally:
        conn.close()

@app.post("/api/facts/{fact_id}/restore")
def restore_fact(fact_id: int):
    conn = get_db()
    try:
        fact = conn.execute("SELECT fact_id, deleted_at FROM facts WHERE fact_id = ?", [fact_id]).fetchone()
        if not fact:
            raise HTTPException(404, "Fact not found")
        if not fact["deleted_at"]:
            return {"ok": True, "fact_id": fact_id, "already_active": True}
        conn.execute(
            "UPDATE facts SET deleted_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?",
            [fact_id],
        )
        fts_upsert_fact(conn, fact_id)
        conn.commit()
        return {"ok": True, "fact_id": fact_id}
    finally:
        conn.close()

@app.post("/api/facts/bulk")
def bulk_facts(data: dict):
    conn = get_db()
    try:
        raw_ids = data.get("ids") or []
        ids = []
        for x in raw_ids:
            try:
                ids.append(int(x))
            except (ValueError, TypeError):
                raise HTTPException(400, f"无效的 fact ID: {x}")
        if not ids:
            raise HTTPException(400, "No ids provided")
        action = (data.get("action") or "").strip()
        placeholders = ",".join(["?"] * len(ids))
        rows = conn.execute(
            f"SELECT fact_id, content, tags, deleted_at FROM facts WHERE fact_id IN ({placeholders})",
            ids,
        ).fetchall()
        if not rows:
            return {"ok": True, "affected": 0}

        if action == "soft_delete":
            for r in rows:
                if r["deleted_at"]:
                    continue
                fts_remove_fact(conn, r["fact_id"], r["content"], r["tags"] or "")
                conn.execute(
                    "UPDATE facts SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?",
                    [r["fact_id"]],
                )
        elif action == "restore":
            for r in rows:
                if not r["deleted_at"]:
                    continue
                conn.execute(
                    "UPDATE facts SET deleted_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?",
                    [r["fact_id"]],
                )
                fts_upsert_fact(conn, r["fact_id"])
        elif action == "hard_delete":
            for r in rows:
                fts_remove_fact(conn, r["fact_id"], r["content"], r["tags"] or "")
                conn.execute("DELETE FROM fact_entities WHERE fact_id = ?", [r["fact_id"]])
                conn.execute("DELETE FROM facts WHERE fact_id = ?", [r["fact_id"]])
        elif action == "set_category":
            category = (data.get("category") or "").strip()
            if not category:
                raise HTTPException(400, "Missing category")
            conn.execute(
                f"UPDATE facts SET category = ?, updated_at = CURRENT_TIMESTAMP WHERE fact_id IN ({placeholders})",
                [category, *ids],
            )
        elif action == "set_tags":
            tags = (data.get("tags") or "").strip()
            conn.execute(
                f"UPDATE facts SET tags = ?, updated_at = CURRENT_TIMESTAMP WHERE fact_id IN ({placeholders})",
                [tags, *ids],
            )
            for r in rows:
                if not r["deleted_at"]:
                    fts_upsert_fact(conn, r["fact_id"])
        elif action == "add_tags":
            append_tags = (data.get("tags") or "").strip()
            if not append_tags:
                raise HTTPException(400, "Missing tags")
            for r in rows:
                existing_tags = (r["tags"] or "").strip()
                new_tags_set = set(t.strip() for t in existing_tags.split(",") if t.strip())
                for t in append_tags.split(","):
                    t = t.strip()
                    if t:
                        new_tags_set.add(t)
                merged = ",".join(sorted(new_tags_set))
                conn.execute("UPDATE facts SET tags = ?, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?", [merged, r["fact_id"]])
                if not r["deleted_at"]:
                    fts_upsert_fact(conn, r["fact_id"])
        elif action == "remove_tags":
            remove_tags_set = set(t.strip() for t in (data.get("tags") or "").split(",") if t.strip())
            if not remove_tags_set:
                raise HTTPException(400, "Missing tags")
            for r in rows:
                existing_tags = set(t.strip() for t in (r["tags"] or "").split(",") if t.strip())
                remaining = existing_tags - remove_tags_set
                merged = ",".join(sorted(remaining))
                conn.execute("UPDATE facts SET tags = ?, updated_at = CURRENT_TIMESTAMP WHERE fact_id = ?", [merged, r["fact_id"]])
                if not r["deleted_at"]:
                    fts_upsert_fact(conn, r["fact_id"])
        else:
            raise HTTPException(400, "Unsupported action")

        conn.commit()
        return {"ok": True, "affected": len(rows), "action": action}
    finally:
        conn.close()

@app.get("/api/facts/export")
def export_facts():
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT fact_id, content, category, tags, trust_score, retrieval_count, "
            "helpful_count, created_at, updated_at, deleted_at FROM facts ORDER BY fact_id"
        ).fetchall()
        facts = []
        for r in rows:
            d = dict(r)
            d["entities"] = [
                e["name"] for e in conn.execute("""
                    SELECT e.name FROM entities e
                    JOIN fact_entities fe ON e.entity_id = fe.entity_id
                    WHERE fe.fact_id = ?
                """, [d["fact_id"]]).fetchall()
            ]
            facts.append(d)
        return JSONResponse(
            content={"facts": facts, "exported_at": datetime.now().isoformat()},
            headers={"Content-Disposition": "attachment; filename=hermes-memory-backup.json"},
        )
    finally:
        conn.close()

@app.post("/api/facts/import")
def import_facts(data: dict):
    """Import facts from a JSON backup file (export format)."""
    facts_list = data.get("facts", [])
    if not facts_list:
        raise HTTPException(400, "No facts in import data")
    conn = get_db()
    try:
        imported = 0
        for f in facts_list:
            content = (f.get("content") or "").strip()
            if not content:
                continue
            category = f.get("category", "general")
            tags = (f.get("tags") or "").strip()
            trust_score = min(max(float(f.get("trust_score", 0.5)), 0.0), 1.0)
            cursor = conn.execute(
                "INSERT INTO facts (content, category, tags, trust_score) VALUES (?, ?, ?, ?)",
                [content, category, tags, trust_score],
            )
            new_id = cursor.lastrowid
            fts_upsert_fact(conn, new_id)
            # 重建实体关联
            for ename in f.get("entities", []):
                ename = str(ename).strip()
                if not ename:
                    continue
                entity = conn.execute(
                    "SELECT entity_id FROM entities WHERE name = ?", [ename]
                ).fetchone()
                if not entity:
                    cur = conn.execute("INSERT INTO entities (name) VALUES (?)", [ename])
                    eid = cur.lastrowid
                else:
                    eid = entity["entity_id"]
                conn.execute(
                    "INSERT OR IGNORE INTO fact_entities (fact_id, entity_id) VALUES (?, ?)",
                    [new_id, eid],
                )
            imported += 1
        conn.commit()
        return {"ok": True, "imported": imported, "skipped": len(facts_list) - imported}
    finally:
        conn.close()

@app.get("/api/tags")
def list_tags():
    """Return all unique tags across active facts."""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT DISTINCT tags FROM facts WHERE deleted_at IS NULL AND tags IS NOT NULL AND TRIM(tags) != ''"
        ).fetchall()
        all_tags = set()
        for r in rows:
            for t in r[0].split(","):
                t = t.strip()
                if t:
                    all_tags.add(t)
        return {"tags": sorted(all_tags)}
    finally:
        conn.close()

@app.get("/api/stats")
def get_stats():
    conn = get_db()
    try:
        total = conn.execute("SELECT COUNT(*) FROM facts WHERE deleted_at IS NULL").fetchone()[0]
        deleted_total = conn.execute("SELECT COUNT(*) FROM facts WHERE deleted_at IS NOT NULL").fetchone()[0]
        by_category = conn.execute(
            "SELECT category, COUNT(*) as count FROM facts WHERE deleted_at IS NULL GROUP BY category ORDER BY count DESC"
        ).fetchall()
        avg_trust = conn.execute("SELECT AVG(trust_score) FROM facts WHERE deleted_at IS NULL").fetchone()[0] or 0
        entity_count = conn.execute("SELECT COUNT(*) FROM entities").fetchone()[0]
        session_count = 0
        try:
            sconn = get_session_db()
            session_count = sconn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
            sconn.close()
        except Exception:
            logger.warning("Failed to count sessions from state.db")
        return {
            "total_facts": total,
            "deleted_facts": deleted_total,
            "by_category": [dict(r) for r in by_category],
            "avg_trust": round(avg_trust, 2),
            "entity_count": entity_count,
            "total_sessions": session_count,
        }
    finally:
        conn.close()

@app.get("/api/facts")
def list_facts(
    q: Optional[str] = Query(None, description="keyword"),
    category: Optional[str] = Query(None, description="category"),
    sort: str = Query("trust", description="trust/date/retrieval"),
    quick: Optional[str] = Query(None, description="recent7|lowtrust|notag|hot"),
    include_deleted: str = Query("active", description="active|only|all"),
    limit: int = Query(50, le=200),
    offset: int = Query(0),
):
    conn = get_db()
    try:
        where_clauses = []
        params = []

        use_fts = True
        if q:
            # FTS5 unicode61 tokenizer 不分割CJK连续字符串
            # 对查询和索引内容都做 cjk_tokenize 确保字符级搜索
            fts_ops = {"AND", "OR", "NOT", "NEAR", "*"}
            q_fts = cjk_tokenize(q)
            tokens = q_fts.strip().split()
            has_operator = any(t.upper() in fts_ops for t in tokens)
            if not has_operator:
                q_fts = " ".join(t + "*" for t in tokens)
            where_clauses.append("facts_fts MATCH ?")
            params.append(q_fts)
        if category and category != "all":
            where_clauses.append("category = ?")
            params.append(category)

        if include_deleted == "only":
            where_clauses.append("deleted_at IS NOT NULL")
        elif include_deleted != "all":
            where_clauses.append("deleted_at IS NULL")

        if quick == "recent7":
            where_clauses.append("datetime(created_at) >= datetime('now', '-7 day')")
        elif quick == "lowtrust":
            where_clauses.append("trust_score < 0.4")
        elif quick == "notag":
            where_clauses.append("(tags IS NULL OR TRIM(tags) = '')")
        elif quick == "hot":
            where_clauses.append("retrieval_count >= 10")

        where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

        sort_map = {
            "trust": "trust_score DESC",
            "trust_asc": "trust_score ASC",
            "date": "created_at DESC",
            "date_asc": "created_at ASC",
            "retrieval": "retrieval_count DESC",
        }
        order = sort_map.get(sort, "trust_score DESC")

        if q:
            sql = f"""
                SELECT f.fact_id, f.content, f.category, f.tags, f.trust_score,
                       f.retrieval_count, f.helpful_count, f.created_at, f.updated_at, f.deleted_at
                FROM facts f
                JOIN facts_fts ON f.fact_id = facts_fts.rowid
                WHERE {where_sql}
                ORDER BY rank, {order}
                LIMIT ? OFFSET ?
            """
        else:
            sql = f"""
                SELECT fact_id, content, category, tags, trust_score,
                       retrieval_count, helpful_count, created_at, updated_at, deleted_at
                FROM facts
                WHERE {where_sql}
                ORDER BY {order}
                LIMIT ? OFFSET ?
            """

        try:
            params.extend([limit, offset])
            rows = conn.execute(sql, params).fetchall()
            if q:
                count_sql = f"""
                    SELECT COUNT(*) FROM facts f
                    JOIN facts_fts ON f.fact_id = facts_fts.rowid
                    WHERE {where_sql}
                """
                total = conn.execute(count_sql, params[:-2]).fetchone()[0]
            else:
                total = conn.execute(
                    f"SELECT COUNT(*) FROM facts WHERE {where_sql}",
                    params[:-2],
                ).fetchone()[0]
        except sqlite3.OperationalError:
            # FTS5 查询语法错误时降级为 LIKE 搜索
            if q:
                where_clauses = [c for c in where_clauses if "facts_fts MATCH" not in c]
                like_q = f"%{q}%"
                where_clauses.append("(facts.content LIKE ? OR facts.tags LIKE ?)")
                params = [like_q, like_q]  # reset params for LIKE
                if category and category != "all":
                    where_clauses.append("category = ?")
                    params.append(category)
                if include_deleted == "only":
                    where_clauses.append("deleted_at IS NOT NULL")
                elif include_deleted != "all":
                    where_clauses.append("deleted_at IS NULL")
                where_sql = " AND ".join(where_clauses)
                # Simple direct query without FTS join
                sql = f"""
                    SELECT fact_id, content, category, tags, trust_score,
                           retrieval_count, helpful_count, created_at, updated_at, deleted_at
                    FROM facts
                    WHERE {where_sql}
                    ORDER BY {order}
                    LIMIT ? OFFSET ?
                """
                params.extend([limit, offset])
                rows = conn.execute(sql, params).fetchall()
                count_sql = f"SELECT COUNT(*) FROM facts WHERE {where_sql}"
                total = conn.execute(count_sql, params[:-2]).fetchone()[0]
            else:
                raise  # non-FTS errors should still propagate

        facts = []
        # 批量获取实体（修复 N+1 查询）
        if rows:
            fact_ids = [r["fact_id"] for r in rows]
            placeholders = ",".join(["?"] * len(fact_ids))
            entity_rows = conn.execute(f"""
                SELECT fe.fact_id, e.name, e.entity_type, e.aliases
                FROM entities e
                JOIN fact_entities fe ON e.entity_id = fe.entity_id
                WHERE fe.fact_id IN ({placeholders})
            """, fact_ids).fetchall()
            from collections import defaultdict
            entity_map = defaultdict(list)
            for er in entity_rows:
                entity_map[er["fact_id"]].append(dict(er))
        else:
            entity_map = {}

        for r in rows:
            d = dict(r)
            d["entities"] = entity_map.get(d["fact_id"], [])
            d["created_at"] = d["created_at"][:19] if d["created_at"] else ""
            d["updated_at"] = d["updated_at"][:19] if d["updated_at"] else ""
            d["deleted_at"] = d["deleted_at"][:19] if d.get("deleted_at") else ""
            facts.append(d)

        return {
            "facts": facts,
            "total": total,
            "limit": limit,
            "offset": offset,
            "quick": quick or "",
            "include_deleted": include_deleted,
        }
    finally:
        conn.close()

@app.get("/api/facts/{fact_id}")
def get_fact(fact_id: int):
    conn = get_db()
    try:
        row = conn.execute("SELECT fact_id, content, category, tags, trust_score, retrieval_count, helpful_count, created_at, updated_at, deleted_at FROM facts WHERE fact_id = ? AND deleted_at IS NULL", [fact_id]).fetchone()
        if not row:
            raise HTTPException(404, "Fact not found")
        result = dict(row)
        result["entities"] = [
            dict(e) for e in conn.execute("""
                SELECT e.name, e.entity_type, e.aliases FROM entities e
                JOIN fact_entities fe ON e.entity_id = fe.entity_id
                WHERE fe.fact_id = ?
            """, [fact_id]).fetchall()
        ]
        return result
    finally:
        conn.close()

# ─── Entities API ───

@app.get("/api/entities")
def list_entities(q: Optional[str] = None, limit: int = 50):
    conn = get_db()
    try:
        if q:
            rows = conn.execute(
                "SELECT * FROM entities WHERE name LIKE ? OR aliases LIKE ? ORDER BY name LIMIT ?",
                [f"%{q}%", f"%{q}%", limit]
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT e.*, COUNT(fe.fact_id) as fact_count FROM entities e "
                "LEFT JOIN fact_entities fe ON e.entity_id = fe.entity_id "
                "GROUP BY e.entity_id ORDER BY fact_count DESC LIMIT ?",
                [limit]
            ).fetchall()
        return {"entities": [dict(r) for r in rows]}
    finally:
        conn.close()

@app.get("/api/entities/{entity_id}")
def get_entity(entity_id: str, by: str = Query("auto", description="auto|id|name")):
    conn = get_db()
    try:
        row = None
        if by == "id" or (by == "auto" and entity_id.isdigit()):
            try:
                eid = int(entity_id)
                row = conn.execute("SELECT * FROM entities WHERE entity_id = ?", [eid]).fetchone()
            except ValueError:
                pass
        if not row:
            row = conn.execute("SELECT * FROM entities WHERE name = ?", [entity_id]).fetchone()
        if not row:
            raise HTTPException(404, f"Entity '{entity_id}' not found")
        result = dict(row)
        result["facts"] = [
            dict(f) for f in conn.execute("""
                SELECT f.fact_id, f.content, f.category, f.trust_score
                FROM facts f
                JOIN fact_entities fe ON f.fact_id = fe.fact_id
                WHERE fe.entity_id = ?
                ORDER BY f.trust_score DESC
            """, [result["entity_id"]]).fetchall()
        ]
        return result
    finally:
        conn.close()

# ─── Sessions API ───

@app.get("/api/sessions")
def list_sessions(limit: int = 30):
    """List sessions from state.db (NOT from JSONL files)."""
    from datetime import datetime
    conn = get_session_db()
    try:
        # 验证表存在
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'"
        ).fetchone()
        if not tables:
            return {"sessions": []}

        rows = conn.execute("""
            SELECT id, title, message_count, source, model, started_at
            FROM sessions
            ORDER BY started_at DESC
            LIMIT ?
        """, [limit]).fetchall()

        sessions = []
        for r in rows:
            ts = r["started_at"]
            dt = datetime.fromtimestamp(ts) if ts else None
            date_str = dt.strftime("%Y-%m-%d %H:%M") if dt else ""
            title = (r["title"] or "").strip() or "(无标题)"
            sessions.append({
                "id": r["id"],
                "title": title[:120],
                "msgs": r["message_count"] or 0,
                "source": r["source"] or "",
                "model": r["model"] or "",
                "date": date_str,
            })

        return {"sessions": sessions}
    finally:
        conn.close()


@app.get("/api/sessions/{session_id}")
def get_session(session_id: str):
    """Get session messages from state.db (NOT from JSONL files)."""
    # 路径穿越防护
    if "/" in session_id or "\\" in session_id or ".." in session_id:
        raise HTTPException(400, "Invalid session_id")
    conn = get_session_db()
    try:
        rows = conn.execute("""
            SELECT id, role, content, tool_call_id, tool_calls, tool_name,
                   timestamp, finish_reason, reasoning
            FROM messages
            WHERE session_id = ?
            ORDER BY id
        """, [session_id]).fetchall()
        if not rows:
            raise HTTPException(404, f"Session {session_id} not found")
        messages = []
        for r in rows:
            msg = {
                "role": r["role"],
                "content": r["content"] or "",
            }
            if r["tool_call_id"]:
                msg["tool_call_id"] = r["tool_call_id"]
            if r["tool_calls"]:
                try:
                    msg["tool_calls"] = json.loads(r["tool_calls"])
                except (json.JSONDecodeError, TypeError):
                    msg["tool_calls"] = r["tool_calls"]
            if r["tool_name"]:
                msg["tool_name"] = r["tool_name"]
            if r["timestamp"]:
                from datetime import datetime
                dt = datetime.fromtimestamp(r["timestamp"])
                msg["timestamp"] = dt.strftime("%Y-%m-%d %H:%M:%S")
            # Truncate long tool outputs to keep response fast
            if msg.get("role") == "tool" and msg.get("content"):
                if len(msg["content"]) > 500:
                    msg["content"] = msg["content"][:500] + f"\n\n... (truncated, total {len(msg['content'])} chars)"
            messages.append(msg)
        return {"session_id": session_id, "messages": messages, "count": len(messages)}
    finally:
        conn.close()

# ─── Task list (todos) from state.db ───

@app.get("/api/tasks")
def get_tasks():
    """Read tasks from state DB."""
    try:
        conn = get_session_db()
        data = conn.execute(
            "SELECT value FROM state_meta WHERE key = 'current_tasks'"
        ).fetchone()
        conn.close()
        if data:
            return json.loads(data["value"])
        return {"tasks": []}
    except Exception as e:
        return {"error": str(e), "tasks": []}

# ─── Skills API ───

SKILLS_DIR = os.path.expanduser("~/.hermes/skills")

# Load bundled manifest
BUNDLED_SKILLS = set()
_bundled_path = os.path.join(SKILLS_DIR, ".bundled_manifest")
if os.path.isfile(_bundled_path):
    with open(_bundled_path, "r", encoding="utf-8") as _f:
        for _line in _f:
            _line = _line.strip()
            if _line and ":" in _line:
                BUNDLED_SKILLS.add(_line.split(":")[0].strip())

def parse_skill_meta(skill_md_path: str) -> dict:
    """Parse YAML frontmatter and body from a SKILL.md file."""
    result = {"name": "", "description": "", "category": "", "file_path": skill_md_path, "body": "", "installed": False}
    try:
        with open(skill_md_path, "r", encoding="utf-8") as f:
            content = f.read()
        if not content.startswith("---"):
            return result
        end = content.find("---", 3)
        if end == -1:
            return result
        front = content[3:end].strip()
        for line in front.split("\n"):
            if line.startswith("name:"):
                result["name"] = line.split(":", 1)[1].strip().strip('"').strip("'")
            elif line.startswith("description:"):
                d = line.split(":", 1)[1].strip().strip('"').strip("'")
                result["description"] = d
        result["body"] = content[end+3:].strip()
        result["installed"] = result["name"] not in BUNDLED_SKILLS
    except Exception as e:
        logger.warning("Failed to parse skill meta from %s: %s", skill_md_path, e)
    return result

@app.get("/api/skills")
def list_skills():
    """Scan ~/.hermes/skills/ for all SKILL.md files grouped by category."""
    skills = []
    skills_dir = SKILLS_DIR
    if not os.path.isdir(skills_dir):
        return {"skills": [], "total": 0}

    # Skills directly in categories
    for cat_name in sorted(os.listdir(skills_dir)):
        cat_path = os.path.join(skills_dir, cat_name)
        if not os.path.isdir(cat_path) or cat_name.startswith("."):
            continue
        for item in sorted(os.listdir(cat_path)):
            skill_dir = os.path.join(cat_path, item)
            skill_md = os.path.join(skill_dir, "SKILL.md")
            if os.path.isfile(skill_md):
                meta = parse_skill_meta(skill_md)
                meta["category"] = cat_name
                meta["dir"] = item
                skills.append(meta)
            # Also check nested skills (e.g. xianyu-api inside xianyu)
            elif os.path.isdir(skill_dir):
                for sub in sorted(os.listdir(skill_dir)):
                    sub_md = os.path.join(skill_dir, sub, "SKILL.md")
                    if os.path.isfile(sub_md):
                        meta = parse_skill_meta(sub_md)
                        meta["category"] = cat_name
                        meta["dir"] = f"{item}/{sub}"
                        skills.append(meta)

    return {"skills": skills, "total": len(skills)}

@app.get("/api/skills/{skill_name}")
def get_skill(skill_name: str):
    """Find a skill by name and return its full content + linked files."""
    skills_dir = SKILLS_DIR
    if not os.path.isdir(skills_dir):
        raise HTTPException(404, "Skills directory not found")

    for cat_name in sorted(os.listdir(skills_dir)):
        cat_path = os.path.join(skills_dir, cat_name)
        if not os.path.isdir(cat_path) or cat_name.startswith("."):
            continue
        for item in sorted(os.listdir(cat_path)):
            skill_dir = os.path.join(cat_path, item)
            skill_md = os.path.join(skill_dir, "SKILL.md")
            if os.path.isfile(skill_md):
                meta = parse_skill_meta(skill_md)
                if meta["name"] == skill_name:
                    with open(skill_md, "r", encoding="utf-8") as f:
                        raw = f.read()
                    # Remove null bytes and other non-printable characters that break JSON
                    raw = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', raw)
                    meta["full_content"] = raw
                    meta["category"] = cat_name
                    meta["linked_files"] = _scan_skill_files(skill_dir)
                    return meta
            elif os.path.isdir(skill_dir):
                for sub in sorted(os.listdir(skill_dir)):
                    sub_md = os.path.join(skill_dir, sub, "SKILL.md")
                    if os.path.isfile(sub_md):
                        meta = parse_skill_meta(sub_md)
                        if meta["name"] == skill_name:
                            with open(sub_md, "r", encoding="utf-8") as f:
                                raw = f.read()
                            raw = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', raw)
                            meta["full_content"] = raw
                            meta["category"] = cat_name
                            sub_skill_dir = os.path.join(skill_dir, sub)
                            meta["linked_files"] = _scan_skill_files(sub_skill_dir)
                            return meta
    raise HTTPException(404, f"Skill '{skill_name}' not found")

def _scan_skill_files(skill_dir: str) -> dict:
    """Scan a skill directory for linked files (references/, scripts/, templates/, assets/).
    Returns a dict mapping subdir names to lists of file paths (relative to skill_dir)."""
    result = {}
    for subdir in ["references", "scripts", "templates", "assets"]:
        sub_path = os.path.join(skill_dir, subdir)
        if os.path.isdir(sub_path):
            files = []
            for root, dirs, fnames in os.walk(sub_path):
                # Skip __pycache__ and .pyc
                dirs[:] = [d for d in dirs if d != "__pycache__"]
                for fname in sorted(fnames):
                    if fname.endswith(".pyc"):
                        continue
                    rel = os.path.relpath(os.path.join(root, fname), skill_dir)
                    files.append(rel)
            if files:
                result[subdir] = files
    return result

@app.get("/api/skills/{skill_name}/file")
def get_skill_file(skill_name: str, path: str = Query(..., description="Relative path within skill dir")):
    """Return the content of a linked file within a skill directory.
    Path traversal is prevented."""
    if ".." in path or path.startswith("/"):
        raise HTTPException(400, "Invalid path")
    skills_dir = SKILLS_DIR
    if not os.path.isdir(skills_dir):
        raise HTTPException(404, "Skills directory not found")
    # Find the skill directory
    for cat_name in sorted(os.listdir(skills_dir)):
        cat_path = os.path.join(skills_dir, cat_name)
        if not os.path.isdir(cat_path) or cat_name.startswith("."):
            continue
        for item in sorted(os.listdir(cat_path)):
            skill_dir = os.path.join(cat_path, item)
            skill_md = os.path.join(skill_dir, "SKILL.md")
            if os.path.isfile(skill_md):
                meta = parse_skill_meta(skill_md)
                if meta["name"] == skill_name:
                    file_path = os.path.normpath(os.path.join(skill_dir, path))
                    if not file_path.startswith(os.path.normpath(skill_dir)):
                        raise HTTPException(400, "Path traversal detected")
                    if not os.path.isfile(file_path):
                        raise HTTPException(404, f"File '{path}' not found")
                    with open(file_path, "r", encoding="utf-8") as f:
                        content = f.read()
                    content = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', content)
                    return {"name": path, "content": content}
            elif os.path.isdir(skill_dir):
                for sub in sorted(os.listdir(skill_dir)):
                    sub_skill_dir = os.path.join(skill_dir, sub)
                    sub_md = os.path.join(sub_skill_dir, "SKILL.md")
                    if os.path.isfile(sub_md):
                        meta = parse_skill_meta(sub_md)
                        if meta["name"] == skill_name:
                            file_path = os.path.normpath(os.path.join(sub_skill_dir, path))
                            if not file_path.startswith(os.path.normpath(sub_skill_dir)):
                                raise HTTPException(400, "Path traversal detected")
                            if not os.path.isfile(file_path):
                                raise HTTPException(404, f"File '{path}' not found")
                            with open(file_path, "r", encoding="utf-8") as f:
                                content = f.read()
                            content = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', content)
                            return {"name": path, "content": content}
    raise HTTPException(404, f"Skill '{skill_name}' not found")

# ─── Frontend ───

@app.get("/", response_class=HTMLResponse)
def index():
    return HTMLResponse(HTML_TEMPLATE)


# ─── HTML Template ───

HTML_TEMPLATE = r"""

<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🧠</text></svg>">
<title>记忆浏览器</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root {
  --bg: #f8fafc;
  --card: #ffffff;
  --border: #e4ecfc;
  --text: #0f172a;
  --text2: #64748b;
  --brand: #2563eb;
  --brand-hover: #1d4ed8;
  --brand-light: #eff6ff;
  --brand-mid: #bfdbfe;
  --green: #059669;
  --green-light: #ecfdf5;
  --amber: #d97706;
  --amber-light: #fffbeb;
  --red: #dc2626;
  --red-light: #fef2f2;
  --radius: 10px;
  --shadow: 0 1px 3px rgba(0,0,0,.06), 0 1px 2px rgba(0,0,0,.04);
  --shadow-hover: 0 8px 24px rgba(0,0,0,.08), 0 2px 6px rgba(0,0,0,.04);
  --font: 'Plus Jakarta Sans', 'PingFang SC', 'Microsoft YaHei', -apple-system, sans-serif;
  --toast-bg: rgba(5,150,105,.92);
  --toast-e: rgba(220,38,38,.92);
  --bulk-bg: rgba(255,255,255,.95);
  --hover: #f1f5f9;
}
body.dark {
  --bg: #0f172a;
  --card: #1e293b;
  --border: #334155;
  --text: #f1f5f9;
  --text2: #94a3b8;
  --brand: #3b82f6;
  --brand-hover: #60a5fa;
  --brand-light: #1e3a5f;
  --brand-mid: #3b82f6;
  --green: #34d399;
  --green-light: #064e3b;
  --amber: #fbbf24;
  --amber-light: #451a03;
  --red: #f87171;
  --red-light: #450a0a;
  --shadow: 0 1px 3px rgba(0,0,0,.3);
  --shadow-hover: 0 8px 24px rgba(0,0,0,.4);
  --toast-bg: rgba(52,211,153,.9);
  --toast-e: rgba(248,113,113,.9);
  --bulk-bg: rgba(30,41,59,.95);
  --hover: #1e293b;
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: var(--font);
  background: var(--bg);
  color: var(--text);
  line-height: 1.6;
  padding: 0;
  min-height: 100vh;
  transition: background .2s, color .2s;
}
#app { max-width: 1200px; margin: 0 auto; padding: 40px 24px 100px; }

/* Header */
.header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 32px; padding-bottom: 20px;
  border-bottom: 1px solid var(--border);
}
.header h1 {
  font-size: 22px; font-weight: 700;
  color: var(--text); letter-spacing: -0.3px;
  display: flex; align-items: center; gap: 8px;
}
.header h1 small { font-size: 13px; font-weight: 500; color: var(--text2); }
.header-actions { display: flex; gap: 10px; align-items: center; }

/* Dark Mode Toggle */
.theme-toggle {
  width: 36px; height: 36px; border-radius: 50%;
  border: 1px solid var(--border); background: var(--card);
  cursor: pointer; font-size: 16px; display: flex;
  align-items: center; justify-content: center;
  transition: all .15s;
}
.theme-toggle:hover {
  border-color: var(--brand); background: var(--brand-light);
  transform: translateY(-1px);
}

/* Stats Bar */
.stats {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 12px; margin-bottom: 28px;
}
.stat-card {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 16px 20px;
  position: relative; overflow: hidden;
  transition: box-shadow .2s, transform .15s; cursor: default;
}
.stat-card:hover { box-shadow: var(--shadow-hover); transform: translateY(-1px); }
.stat-card::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
}
.stat-card:nth-child(1)::before { background: var(--brand); }
.stat-card:nth-child(2)::before { background: var(--green); }
.stat-card:nth-child(3)::before { background: var(--amber); }
.stat-card:nth-child(4)::before { background: #8b5cf6; }
.stat-card .sval { font-size: 28px; font-weight: 700; color: var(--text); line-height: 1.2; }
.stat-card .slbl { font-size: 12px; font-weight: 500; color: var(--text2); text-transform: none; letter-spacing: .5px; margin-top: 2px; }

/* Tabs */
.tabs {
  display: flex; gap: 0; margin-bottom: 24px;
  border-bottom: 1px solid var(--border);
}
.tab {
  padding: 10px 20px; font-size: 14px; font-weight: 500;
  color: var(--text2); cursor: pointer; border: none; background: none;
  position: relative; transition: color .15s;
  font-family: var(--font);
}
.tab:hover { color: var(--text); }
.tab.active { color: var(--brand); }
.tab.active::after {
  content: ''; position: absolute; bottom: -1px; left: 0; right: 0;
  height: 2px; background: var(--brand); border-radius: 1px 1px 0 0;
}

/* Toolbar */
.toolbar {
  display: flex; gap: 10px; align-items: center; margin-bottom: 20px;
  flex-wrap: wrap;
}
.toolbar .search-wrap {
  position: relative; flex: 1; min-width: 200px;
}
.toolbar .search-wrap input {
  width: 100%; padding: 9px 14px 9px 36px;
  border: 1px solid var(--border); border-radius: 8px;
  font-size: 13px; font-family: var(--font);
  background: var(--card); color: var(--text);
  outline: none; transition: border-color .15s, box-shadow .15s;
}
.toolbar .search-wrap input:focus {
  border-color: var(--brand); box-shadow: 0 0 0 3px rgba(37,99,235,.12);
}
.toolbar .search-wrap .s-icon {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  color: var(--text2); font-size: 13px; pointer-events: none;
}
.toolbar select {
  padding: 9px 14px; border: 1px solid var(--border); border-radius: 8px;
  font-size: 13px; font-family: var(--font); background: var(--card);
  color: var(--text); outline: none; cursor: pointer;
  transition: border-color .15s;
}
.toolbar select:focus { border-color: var(--brand); box-shadow: 0 0 0 3px rgba(37,99,235,.12); }

/* Buttons */
.btn {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 9px 16px; font-size: 13px; font-weight: 500;
  border: 1px solid var(--border); border-radius: 8px;
  background: var(--card); color: var(--text); cursor: pointer;
  transition: all .15s; font-family: var(--font); white-space: nowrap;
}
.btn:hover {
  border-color: var(--brand); background: var(--brand-light);
  transform: translateY(-1px); box-shadow: 0 2px 8px rgba(0,0,0,.06);
}
.btn-primary {
  background: var(--brand); color: #fff; border-color: var(--brand);
}
.btn-primary:hover {
  background: var(--brand-hover); border-color: var(--brand-hover); color: #fff;
}
.btn-danger { color: var(--red); }
.btn-danger:hover {
  background: var(--red-light); border-color: var(--red); color: var(--red);
}
.btn:disabled { opacity: .35; pointer-events: none; }

/* Copy toast hint */
.copy-hint {
  position: fixed; bottom: 60px; left: 50%; transform: translateX(-50%);
  background: var(--text); color: var(--card); padding: 8px 16px;
  border-radius: 8px; font-size: 12px; font-weight: 500;
  opacity: 0; transition: opacity .2s; pointer-events: none; z-index: 100;
}
.copy-hint.show { opacity: 1; }

/* Fact Cards */
.fact-list { display: flex; flex-direction: column; gap: 10px; }
.fact {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 18px 20px;
  transition: all .2s; cursor: pointer;
  animation: cardIn .25s ease both;
  position: relative;
}
@keyframes cardIn {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}
.fact:hover { box-shadow: var(--shadow-hover); border-color: var(--brand-mid); }
.fact.sel {
  background: var(--brand-light);
  border-color: var(--brand);
  box-shadow: 0 2px 8px rgba(37,99,235,.1);
}
.fact .content {
  font-size: 14px; line-height: 1.7; margin-bottom: 10px;
  display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical;
  overflow: hidden; word-break: break-word; transition: all .15s;
}
.fact .content.expanded { -webkit-line-clamp: unset; }
.fact .content-expand {
  font-size: 12px; color: var(--brand); cursor: pointer;
  margin-top: 2px; user-select: none; display: inline-block;
}
.fact .content-expand:hover { color: var(--brand-hover); text-decoration: underline; }
.fact .meta {
  display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
  font-size: 12px; color: var(--text2);
}
.fact .meta-sep { color: #cbd5e1; font-weight: 300; }
body.dark .fact .meta-sep { color: #475569; }
.fact .fact-id {
  font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
  font-size: 11px; color: #94a3b8; font-weight: 600; cursor: pointer;
  transition: color .15s;
}
.fact .fact-id:hover { color: var(--brand); }
.tag {
  display: inline-flex; padding: 2px 10px; border-radius: 20px;
  font-size: 11px; font-weight: 600; letter-spacing: .3px;
}
.tag.user_pref { background: #e0e7ff; color: #4338ca; }
.tag.project { background: #d1fae5; color: #047857; }
.tag.tool { background: #fef3c7; color: #b45309; }
.tag.general { background: #f1f5f9; color: #475569; }
.tag.trash { background: #fef2f2; color: #dc2626; }
body.dark .tag.user_pref { background: #1e3a5f; color: #93c5fd; }
body.dark .tag.project { background: #064e3b; color: #6ee7b7; }
body.dark .tag.tool { background: #451a03; color: #fcd34d; }
body.dark .tag.general { background: #334155; color: #cbd5e1; }
body.dark .tag.trash { background: #450a0a; color: #fca5a5; }
.tag-pill {
  display: inline-flex; padding: 1px 8px; border-radius: 10px;
  background: #f1f5f9; color: #64748b; font-size: 11px;
  max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
body.dark .tag-pill { background: #334155; color: #94a3b8; }
.trust-dot { display: inline-flex; align-items: center; gap: 3px; }
.trust-dot .dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
.trust-dot .pct { font-size: 11px; color: var(--text2); font-weight: 500; }
.actions {
  margin-left: auto; display: flex; gap: 4px; flex-shrink: 0;
}
.actions .ae, .actions .ad, .actions .ac {
  display: inline-flex; align-items: center; justify-content: center;
  width: 28px; height: 28px; border-radius: 6px; border: none;
  background: transparent; cursor: pointer; font-size: 14px;
  transition: all .15s;
}
.actions .ae:hover { background: var(--brand-light); }
.actions .ad:hover { background: var(--red-light); }
.actions .ac:hover { background: var(--green-light); }

/* Bulk Action Bar */
.bulk-bar {
  position: fixed; bottom: 0; left: 0; right: 0;
  background: var(--bulk-bg); backdrop-filter: blur(14px);
  border-top: 1px solid var(--border); padding: 12px 24px;
  z-index: 150; display: flex; align-items: center; gap: 10px;
  box-shadow: 0 -4px 20px rgba(0,0,0,.06);
  transform: translateY(100%); transition: transform .25s cubic-bezier(.4,0,.2,1);
}
.bulk-bar.show { transform: translateY(0); }
.bulk-bar .bcount {
  background: var(--brand); color: #fff; border-radius: 20px;
  padding: 2px 10px; font-size: 12px; font-weight: 700; min-width: 24px;
  text-align: center;
}
.bulk-bar .blabel { font-size: 13px; color: var(--text2); }
.bulk-bar .bspacer { flex: 1; }

/* Pagination */
.pagination {
  display: flex; align-items: center; justify-content: center;
  gap: 6px; margin-top: 24px;
}
.pagination .btn { min-width: 36px; justify-content: center; }

/* Modal */
.modal-overlay {
  position: fixed; inset: 0; background: rgba(15,23,42,.5);
  z-index: 200; display: flex; align-items: center; justify-content: center;
  animation: fadeIn .15s ease;
}
body.dark .modal-overlay { background: rgba(0,0,0,.6); }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
.modal {
  background: var(--card); border-radius: 14px; padding: 28px 32px;
  max-width: 520px; width: 90%; box-shadow: 0 24px 48px rgba(0,0,0,.15);
  max-height: 85vh; overflow-y: auto;
}
.modal h3 { font-size: 17px; font-weight: 700; margin-bottom: 20px; color: var(--text); }
.modal label { font-size: 13px; font-weight: 500; color: var(--text2); display: block; margin-bottom: 4px; }
.modal input, .modal textarea, .modal select {
  width: 100%; padding: 10px 12px; border: 1px solid var(--border);
  border-radius: 8px; font-size: 13px; font-family: var(--font);
  outline: none; transition: border-color .15s; margin-bottom: 14px;
  background: var(--bg); color: var(--text);
}
.modal input:focus, .modal textarea:focus, .modal select:focus {
  border-color: var(--brand); box-shadow: 0 0 0 3px rgba(37,99,235,.12);
}
.modal textarea { min-height: 80px; resize: vertical; }
.modal .mbtns { display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px; }
.cat-picker { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 16px; }
.cat-picker button {
  padding: 10px; border: 1px solid var(--border); border-radius: 8px;
  background: var(--card); font-size: 13px; font-family: var(--font);
  cursor: pointer; transition: all .15s; color: var(--text);
}
.cat-picker button:hover {
  border-color: var(--brand); background: var(--brand-light); color: var(--brand);
}

/* Toast */
.toast {
  position: fixed; top: 24px; left: 50%; transform: translateX(-50%);
  z-index: 300; padding: 12px 24px; border-radius: 10px; color: #fff;
  font-size: 14px; font-weight: 500; font-family: var(--font);
  box-shadow: 0 8px 24px rgba(0,0,0,.15);
  animation: toastIn .2s ease; white-space: nowrap;
}
@keyframes toastIn { from { opacity: 0; transform: translateX(-50%) translateY(-10px); } to { opacity: 1; transform: translateX(-50%) translateY(0); } }
.toast.s { background: var(--toast-bg); }
.toast.e { background: var(--toast-e); }

/* Entities */
.entity-list { display: flex; flex-direction: column; gap: 8px; }
.entity-item {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 14px 18px;
  cursor: pointer; transition: all .2s;
  animation: cardIn .25s ease both;
}
.entity-item:hover { box-shadow: var(--shadow-hover); border-color: var(--brand-mid); }
.entity-item .ename { font-size: 15px; font-weight: 600; color: var(--text); }
.entity-item .ecount { font-size: 12px; color: var(--text2); margin-top: 2px; }

/* Entity Detail */
.edetail {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 20px; margin-bottom: 16px;
}
.edetail h3 { font-size: 16px; font-weight: 700; margin-bottom: 4px; }
.edetail .esub { font-size: 12px; color: var(--text2); margin-bottom: 16px; }
.edetail .efacts { display: flex; flex-direction: column; gap: 8px; }
.edetail .efact {
  padding: 12px 14px; border: 1px solid var(--border);
  border-radius: 8px; font-size: 13px; line-height: 1.6;
  transition: all .15s;
}
.edetail .efact:hover { border-color: var(--brand-mid); background: var(--brand-light); }
.edetail .efact .emeta { font-size: 11px; color: var(--text2); margin-top: 6px; }

/* Sessions */
.session-list { display: flex; flex-direction: column; gap: 8px; }
.session-card {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 16px 18px;
  cursor: pointer; transition: all .2s;
  animation: cardIn .25s ease both;
}
.session-card:hover { box-shadow: var(--shadow-hover); border-color: var(--brand-mid); }
.session-card .sname {
  font-size: 14px; font-weight: 600; color: var(--text);
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical;
  overflow: hidden; line-height: 1.5;
}
.session-card .sinfo {
  font-size: 12px; color: var(--text2); margin-top: 4px;
  display: flex; gap: 12px; align-items: center; flex-wrap: wrap;
}
.session-card .s-time {
  color: var(--brand); font-weight: 500; font-size: 11px;
}
.session-card .s-date {
  margin-left: auto; color: #94a3b8; font-size: 11px;
}
body.dark .session-card .s-date { color: #64748b; }

/* Chat View - 极简对话 */
.chat-view { max-width: 100%; }
.chat-top {
  display: flex; align-items: center; gap: 10px;
  margin-bottom: 20px; padding-bottom: 16px;
  border-bottom: 1px solid var(--border);
}
.chat-top .ct-back {
  width: 32px; height: 32px; border-radius: 8px;
  border: none; background: var(--brand); color: #fff;
  cursor: pointer; font-size: 14px; display: flex;
  align-items: center; justify-content: center;
  transition: opacity .15s; flex-shrink: 0;
}
.chat-top .ct-back:hover { opacity: .85; }
.chat-top .ct-title {
  font-size: 14px; font-weight: 600; color: var(--text);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  flex: 1; min-width: 0;
}
.chat-top .ct-count { font-size: 12px; color: var(--text2); white-space: nowrap; }

.chat-msgs { padding: 0; }

.msg {
  padding: 10px 16px; font-size: 14px; line-height: 1.7;
  animation: msgIn .2s ease both; word-break: break-word;
  margin-bottom: 8px;
}
@keyframes msgIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}
.msg.user {
  background: var(--brand); color: #fff; margin-left: auto;
  border-radius: 14px 14px 4px 14px;
  max-width: 78%;
}
.msg.assistant {
  background: var(--card); color: var(--text); margin-right: auto;
  border: 1px solid var(--border);
  border-radius: 14px 14px 14px 4px;
  max-width: 90%;
}
.msg.assistant .md { font-size: 14px; line-height: 1.7; }
.msg-time {
  font-size: 10px; color: #94a3b8; margin-top: 4px; text-align: left;
  font-weight: 400;
}
.msg.user .msg-time.user-time { text-align: right; color: rgba(255,255,255,.6); }
body.dark .msg-time { color: #64748b; }
.msg.assistant .md p { margin: 0 0 6px; }
.msg.assistant .md p:last-child { margin-bottom: 0; }
.msg.assistant .md strong { font-weight: 600; }
.msg.assistant .md ul { margin: 4px 0 6px; padding-left: 16px; }
.msg.assistant .md li { margin: 2px 0; }
.msg.assistant code {
  background: #f1f5f9; padding: 1px 4px; border-radius: 3px;
  font-size: 12px; font-family: 'SF Mono', 'Fira Code', monospace;
}
body.dark .msg.assistant code { background: #334155; color: #e2e8f0; }
.msg.assistant .md-table-wrap {
  overflow-x: auto; margin: 6px 0;
}
.msg.assistant .md-table-wrap table {
  border-collapse: collapse; width: 100%; min-width: 300px;
  font-size: 12px; line-height: 1.5;
}
.msg.assistant .md-table-wrap th,
.msg.assistant .md-table-wrap td {
  border: 1px solid var(--border); padding: 4px 8px; text-align: left;
}
.msg.assistant .md-table-wrap th {
  background: var(--brand-light); font-weight: 600;
  color: var(--text);
}
body.dark .msg.assistant .md-table-wrap th { background: #1e3a5f; }

/* Back button (floating) */
.back-btn {
  position: fixed; left: 50%; margin-left: calc(-420px);
  top: 50%; transform: translateY(-50%); z-index: 50;
  width: 36px; height: 36px; border-radius: 50%;
  border: none; background: var(--brand); color: #fff;
  font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center;
  transition: all .15s; box-shadow: 0 2px 8px rgba(37,99,235,.3);
}
.back-btn:hover {
  background: var(--brand-hover);
  transform: translateY(-50%) translateX(-2px);
  box-shadow: 0 4px 12px rgba(37,99,235,.4);
}

/* Empty state */
.empty { text-align: center; padding: 48px 20px; color: var(--text2); font-size: 14px; }
.empty .empty-icon { font-size: 40px; margin-bottom: 12px; opacity: .4; }

/* Keyboard hints */
.kbd-hint {
  position: fixed; bottom: 16px; right: 16px;
  font-size: 11px; color: var(--text2); opacity: .5;
  z-index: 50; pointer-events: none;
}
.kbd-hint kbd {
  display: inline-block; padding: 1px 5px; border-radius: 3px;
  border: 1px solid var(--border); background: var(--card);
  font-family: 'SF Mono', 'Fira Code', monospace; font-size: 10px;
}

/* Skeleton Screen */
.skeleton-list { display: flex; flex-direction: column; gap: 10px; }
.skeleton-card {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 18px 20px;
  animation: skPulse 1.6s ease-in-out infinite;
}
@keyframes skPulse {
  0%, 100% { opacity: .6; }
  50% { opacity: .2; }
}
.skeleton-card .sk-line {
  height: 14px; background: var(--border); border-radius: 4px;
  margin-bottom: 12px;
}
.skeleton-card .sk-line:nth-child(2) { width: 72%; }
.skeleton-card .sk-line:last-child { width: 46%; margin-bottom: 0; }

/* Empty state with action */
.empty-action { margin-top: 16px; }

/* Skill content markdown rendering — polished article style */
.skill-content {
  font-size: 14px; line-height: 1.9; color: var(--text);
}
.skill-content h2 {
  font-size: 20px; font-weight: 700; margin: 32px 0 14px;
  padding-bottom: 8px; border-bottom: 2px solid var(--brand-light);
  color: var(--text); letter-spacing: -0.3px;
}
body.dark .skill-content h2 { border-bottom-color: #1e3a5f; }
.skill-content h3 {
  font-size: 17px; font-weight: 600; margin: 24px 0 10px;
  color: var(--text);
}
.skill-content h4 {
  font-size: 15px; font-weight: 600; margin: 20px 0 8px;
  color: var(--text); opacity: .92;
}
.skill-content p {
  margin: 0 0 14px; color: var(--text);
}
.skill-content ul, .skill-content ol {
  margin: 0 0 14px; padding-left: 22px;
}
.skill-content li {
  margin: 5px 0; line-height: 1.8;
}
.skill-content li::marker { color: var(--brand); }
.skill-content ol li::marker { font-weight: 600; }
.skill-content strong { font-weight: 700; color: var(--text); }
.skill-content hr {
  border: none; border-top: 1px solid var(--border); margin: 28px 0;
}
.skill-content a {
  color: var(--brand); text-decoration: none; font-weight: 500;
  border-bottom: 1px solid transparent; transition: border-color .15s;
}
.skill-content a:hover { border-bottom-color: var(--brand); }
/* Code blocks */
.skill-content pre {
  margin: 16px 0; padding: 16px 18px;
  background: #f8fafc; border: 1px solid var(--border);
  border-radius: 8px; overflow-x: auto; font-size: 13px; line-height: 1.6;
}
.skill-content pre code {
  background: none; padding: 0; border-radius: 0;
  color: #1e293b; font-size: 13px;
}
body.dark .skill-content pre { background: #1e293b; border-color: #334155; }
body.dark .skill-content pre code { color: #e2e8f0; }
/* Inline code */
.skill-content code {
  background: #f1f5f9; padding: 2px 6px; border-radius: 4px;
  font-size: 13px; font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
  color: #e11d48; font-weight: 500;
}
body.dark .skill-content code { background: #334155; color: #f472b6; }
/* Blockquote — tip/note callout */
.skill-content blockquote {
  margin: 16px 0; padding: 14px 18px;
  border-left: 3px solid var(--brand);
  background: var(--brand-light); border-radius: 0 8px 8px 0;
  font-size: 13px; line-height: 1.7; color: var(--text);
}
body.dark .skill-content blockquote { background: #1e3a5f; border-left-color: var(--brand); }
.skill-content blockquote p { margin: 0; }
.skill-content blockquote p + p { margin-top: 8px; }
/* Tables */
.skill-content .md-table-wrap {
  overflow-x: auto; margin: 16px 0;
  border-radius: 8px; border: 1px solid var(--border);
}
.skill-content table {
  border-collapse: collapse; width: 100%; min-width: 450px;
  font-size: 13px; line-height: 1.6;
}
.skill-content th, .skill-content td {
  border: none; padding: 10px 14px; text-align: left;
  border-bottom: 1px solid var(--border);
}
.skill-content th {
  background: var(--brand-light); font-weight: 600;
  font-size: 12px; text-transform: none; letter-spacing: .5px;
  color: var(--text);
}
body.dark .skill-content th { background: #1e3a5f; }
.skill-content tr:last-child td { border-bottom: none; }
.skill-content tr:hover td { background: var(--brand-light); }
body.dark .skill-content tr:hover td { background: #1e293b; }

/* Responsive */
@media (max-width: 640px) {
  #app { padding: 20px 12px 100px; }
  .header { flex-direction: column; align-items: flex-start; gap: 12px; }
  .header h1 { font-size: 18px; }
  .stats { grid-template-columns: repeat(2, 1fr); }
  .toolbar .search-wrap { min-width: 100%; }
  .back-btn { display: none; }
  .modal { padding: 20px; width: 95%; }
  .cat-picker { grid-template-columns: 1fr; }
  .kbd-hint { display: none; }
}
</style>
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
</head>
<body>
<div id="app">
  <!-- Header -->
  <div class="header">
    <h1>🧠 记忆浏览器 <small>Hermes Memory</small></h1>
    <div class="header-actions">
      <button class="theme-toggle" onclick="toggleTheme()" title="切换暗黑模式" id="themeBtn">🌙</button>
      <button class="btn btn-primary" onclick="openAdd()">＋ 新增事实</button>
      <button class="btn" onclick="exportJSON()">📥 导出</button>
      <button class="btn" onclick="document.getElementById('importFile').click()">📤 导入</button>
      <input type="file" id="importFile" accept=".json" style="display:none" onchange="importJSON(this)">
    </div>
  </div>

  <!-- Stats -->
  <div class="stats" id="stats"></div>

  <!-- Tabs -->
  <div class="tabs" id="tabs">
    <button class="tab active" data-tab="facts" onclick="switchTab('facts')">📝 事实</button>
    <button class="tab" data-tab="entities" onclick="switchTab('entities')">🏷️ 实体</button>
    <button class="tab" data-tab="sessions" onclick="switchTab('sessions')">💬 对话</button>
    <button class="tab" data-tab="skills" onclick="switchTab('skills')">🔧 技能</button>
  </div>

  <!-- Toolbar (facts) -->
  <div class="toolbar" id="toolbar">
    <div class="search-wrap">
      <span class="s-icon">🔍</span>
      <input id="search" placeholder="搜索事实..." oninput="onSearch()">
    </div>
    <select id="catFilter" onchange="onSearch()">
      <option value="">全部分类</option>
      <option value="user_pref">用户偏好</option>
      <option value="project">项目</option>
      <option value="tool">工具</option>
      <option value="general">通用</option>
      <option value="trash">🗑️ 回收站</option>
    </select>
    <select id="sortSelect" onchange="onSearch()">
      <option value="trust">按信任度</option>
      <option value="newest">最新优先</option>
      <option value="oldest">最早优先</option>
    </select>
  </div>

  <!-- Content Area -->
  <div id="content"></div>

  <!-- Bulk Action Bar -->
  <div class="bulk-bar" id="bulkBar">
    <span class="bcount" id="bcount">0</span>
    <span class="blabel">已选</span>
    <button class="btn" onclick="toggleAll()">全选/取消</button>
    <span class="bspacer"></span>
    <button class="btn btn-danger" onclick="bulkDel()">🗑️ 删除</button>
    <button class="btn" onclick="bulkRestore()">♻️ 恢复</button>
    <button class="btn" onclick="openBulkCat()">🏷️ 改分类</button>
    <button class="btn" onclick="openBulkTags()">#️⃣ 改标签</button>
    <button class="btn" onclick="openBulkAddTags()">➕ 加标签</button>
    <button class="btn" onclick="openBulkRemoveTags()">➖ 删标签</button>
    <button class="btn btn-danger" onclick="bulkHard()">💀 彻底删除</button>
  </div>
</div>

<script>
const CAT_NAMES = { user_pref:'用户偏好', project:'项目', tool:'工具', general:'通用', trash:'回收站' };
const CAT_LIST = ['user_pref','project','tool','general'];
let sel = new Set();
let allFacts = [];
let currentTab = 'facts';
let viewingSession = null;
let viewingSkill = null;
let page = 1, totalPages = 1, pageSize = 20;

// ===== State Persistence =====
function saveState() {
  const s = { tab:currentTab, cat:g('catFilter').value,
    sort:g('sortSelect').value, page, sessionId:viewingSession, skill:viewingSkill };
  // Save search per-tab so switching tabs doesn't bleed search text
  s['s_' + currentTab] = g('search').value;
  try { sessionStorage.setItem('mbstate', JSON.stringify(s)); } catch(e) {}
}
function loadState() {
  try {
    const raw = sessionStorage.getItem('mbstate');
    if (!raw) return;
    const s = JSON.parse(raw);
    if (s.tab) g('tabs').querySelectorAll('.tab').forEach(t=>{
      t.classList.toggle('active', t.dataset.tab===s.tab);
    });
    // Restore search only for the current tab
    if (s.tab && s['s_' + s.tab]) g('search').value = s['s_' + s.tab];
    if (s.cat) g('catFilter').value = s.cat;
    if (s.sort) g('sortSelect').value = s.sort;
    if (s.page) page = s.page;
    if (s.tab) currentTab = s.tab;
    if (s.sessionId) viewingSession = s.sessionId;
    if (s.skill) viewingSkill = s.skill;
  } catch(e) {}
}

// ===== Helpers =====
function g(id) { return document.getElementById(id); }
function q(s) { return document.querySelector(s); }
const BASE = '/api';

async function api(path, opts={}) {
  const r = await fetch(BASE+path, { headers:{'Accept':'application/json'}, ...opts });
  if (!r.ok) { const t = await r.text().catch(()=>'');
    throw new Error(r.status + (t ? ': '+t.slice(0,80) : '')); }
  return r.json();
}

function toast(msg, type='s', undoFn) {
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  if (undoFn) {
    const u = document.createElement('span');
    u.textContent = ' 撤销';
    u.style.cssText = 'margin-left:12px;font-weight:700;cursor:pointer;text-decoration:underline;opacity:.9';
    u.onclick = () => { clearTimeout(t._timer); t.remove(); undoFn(); };
    t.appendChild(u);
  }
  document.body.appendChild(t);
  t._timer = setTimeout(() => {
    t.style.opacity = '0'; t.style.transition = 'opacity .3s';
    setTimeout(() => t.remove(), 300);
  }, 4000);
}

function closeModal(el) { const o = el.closest('.modal-overlay'); if(o) o.remove(); }
function esc(s) {
  if (!s) return '';
  return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#x27;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function skeletonCards(count) {
  let h = '<div class="skeleton-list">';
  for (let i=0; i<count; i++) {
    h += '<div class="skeleton-card"><div class="sk-line"></div><div class="sk-line"></div><div class="sk-line"></div></div>';
  }
  h += '</div>';
  return h;
}

function trapFocus(modalEl) {
  const f = modalEl.querySelectorAll('input,textarea,select,button,[tabindex]:not([tabindex="-1"])');
  if (!f.length) return;
  const first = f[0], last = f[f.length-1];
  setTimeout(()=>first.focus(),80);
  modalEl.addEventListener('keydown',function h(e){
    if(e.key!=='Tab') return;
    if(e.shiftKey){if(document.activeElement===first){e.preventDefault();last.focus();}}
    else if(document.activeElement===last){e.preventDefault();first.focus();}
  });
}

// ===== Dark Mode =====
function toggleTheme() {
  const b = document.body;
  b.classList.toggle('dark');
  const isDark = b.classList.contains('dark');
  g('themeBtn').textContent = isDark ? '☀️' : '🌙';
  try { localStorage.setItem('mb-theme', isDark ? 'dark' : 'light'); } catch(e) {}
}
(function(){
  try {
    if (localStorage.getItem('mb-theme') === 'dark') {
      document.body.classList.add('dark');
      document.getElementById('themeBtn').textContent = '☀️';
    }
  } catch(e) {}
})();

// ===== Copy to Clipboard =====
function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(()=>{});
  }
  // Show brief hint
  let hint = document.querySelector('.copy-hint');
  if (!hint) {
    hint = document.createElement('div');
    hint.className = 'copy-hint';
    hint.textContent = '已复制';
    document.body.appendChild(hint);
  }
  hint.classList.add('show');
  clearTimeout(hint._timer);
  hint._timer = setTimeout(() => hint.classList.remove('show'), 1200);
}

// ===== Search by ID =====
function searchByID(id) {
  g('search').value = `#${id}`;
  g('catFilter').value = '';
  page = 1;
  renderFacts();
}

// ===== Stats =====
async function renderStats() {
  try {
    const d = await api('/stats');
    const trustAvg = d.total_facts ? (d.avg_trust*100).toFixed(0) : 0;
    g('stats').innerHTML = `
      <div class="stat-card"><div class="sval">${d.total_facts||0}</div><div class="slbl">事实总数</div></div>
      <div class="stat-card"><div class="sval">${d.entity_count||0}</div><div class="slbl">实体总数</div></div>
      <div class="stat-card"><div class="sval">${trustAvg}%</div><div class="slbl">平均信任度</div></div>
      <div class="stat-card"><div class="sval">${d.total_sessions||0}</div><div class="slbl">对话数</div></div>
    `;
  } catch(e) { g('stats').innerHTML = ''; }
}

// ===== Tabs =====
function switchTab(tab) {
  currentTab = tab;
  detailEntity = null;
  viewingSession = null;
  viewingSkill = null;
  sel = new Set(); updateBulkBar();
  g('tabs').querySelectorAll('.tab').forEach(t=>t.classList.toggle('active',t.dataset.tab===tab));
  g('toolbar').style.display = tab==='facts' ? 'flex' : 'none';
  saveState();
  if (tab==='facts') renderFacts();
  else if (tab==='entities') renderEntities();
  else if (tab==='skills') { g('toolbar').style.display='none'; renderSkills(); }
  else renderSessions();
}

// ===== Facts =====
async function renderFacts() {
  const q = g('search').value.trim();
  const cat = g('catFilter').value;
  const sort = g('sortSelect').value;
  g('content').innerHTML = skeletonCards(5);
  try {
    const params = new URLSearchParams();
    params.set('limit', pageSize);
    params.set('offset', (page-1) * pageSize);
    // Map frontend sort values to backend API values
    const sortMap = { newest: 'date', oldest: 'date_asc', trust: 'trust', retrieval: 'retrieval' };
    params.set('sort', sortMap[sort] || sort);
    if (q) params.set('q', q);
    if (cat === 'trash') {
      params.set('include_deleted', 'only');
    } else if (cat) {
      params.set('category', cat);
    }
    const d = await api('/facts?' + params.toString());
    allFacts = d.facts || d.data || d.results || d;
    const total = d.total || d.total_count || allFacts.length;
    totalPages = Math.max(1, Math.ceil(total / pageSize));

    if (!allFacts.length) {
      g('content').innerHTML = '<div class=\"empty\"><div class=\"empty-icon\">📭</div>没有找到事实<div class=\"empty-action\"><button class=\"btn btn-primary\" onclick=\"openAdd()\">＋ 新增事实</button></div></div>';
      return;
    }

    let html = '<div class="fact-list">';
    allFacts.forEach(f => {
      const cc = (f.category||'general').replace(/^deleted_/,'');
      const catName = CAT_NAMES[cc] || cc;
      const safeContent = esc(f.content);
      const isLong = safeContent.length > 120;
      const tc = f.trust_score >= 0.7 ? '#059669' : f.trust_score >= 0.4 ? '#d97706' : '#dc2626';
      const tpct = (f.trust_score*100).toFixed(0);
      // Dark mode dot colors
      const isDark = document.body.classList.contains('dark');
      const dotColor = f.trust_score >= 0.7 ? (isDark ? '#34d399' : '#059669') : f.trust_score >= 0.4 ? (isDark ? '#fbbf24' : '#d97706') : (isDark ? '#f87171' : '#dc2626');
      const tind = `<span class="trust-dot"><span class="dot" style="background-color:${dotColor}"></span><span class="pct">${tpct}%</span></span>`;
      const dt = (f.created_at||f.updated_at||'').replace(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}).*/,'$2-$3 $4:$5');
      const tags = (f.tags||'').split(',').filter(t=>t.trim()).map(t=>`<span class="tag-pill">#${esc(t.trim())}</span>`).join('');
      const isSel = sel.has(f.fact_id);

      html += `<div class="fact ${isSel?'sel':''}" data-fid="${f.fact_id}">
        <div class="content${isLong?'':' expanded'}" onclick="showDetail(${f.fact_id})">${safeContent}</div>
        ${isLong ? `<div class="content-expand" onclick="event.stopPropagation();this.parentElement.querySelector('.content').classList.toggle('expanded');this.textContent=this.textContent==='展开全文'?'收起':'展开全文'">展开全文</div>` : ''}
        <div class="meta">
          <input type="checkbox" class="sel-cb" ${isSel?'checked':''} onclick="event.stopPropagation();toggleSel(${f.fact_id})" style="margin:0;cursor:pointer;accent-color:var(--brand)">
          <span class="tag ${cc}">${catName}</span>
          <span class="meta-sep">·</span>
          ${tind}
          <span class="meta-sep">·</span>
          <span class="fact-id" onclick="event.stopPropagation();searchByID(${f.fact_id})">#${f.fact_id}</span>
          <span class="meta-sep">·</span>
          <span>${dt}</span>
          ${tags ? `<span class="meta-sep">·</span>${tags}` : ''}
          <div class="actions">
            <button class="ae" title="详情" onclick="event.stopPropagation();showDetail(${f.fact_id})">👁️</button>
            <button class="ac" title="复制" data-cc="${esc(f.content)}" onclick="event.stopPropagation();copyText(this.dataset.cc)">📋</button>
            <button class="ae" data-eid="${f.fact_id}"
              data-ec="${esc(safeContent)}"
              data-eca="${esc(f.category||'general')}"
              data-etag="${esc(f.tags||'')}"
              data-et="${f.trust_score}"
              onclick="event.stopPropagation();openEditFrom(this)">✏️</button>
            <button class="ad" onclick="event.stopPropagation();del(${f.fact_id})">🗑️</button>
          </div>
        </div>
      </div>`;
    });
    html += '</div>';

    // Pagination
    if (totalPages > 1) {
      html += '<div class="pagination">';
      html += `<button class="btn" onclick="page=${Math.max(1,page-1)};renderFacts()" ${page<=1?'disabled':''}>‹</button>`;
      for (let i=1; i<=totalPages; i++) {
        html += `<button class="btn ${i===page?'btn-primary':''}" onclick="page=${i};renderFacts()">${i}</button>`;
      }
      html += `<button class="btn" onclick="page=${Math.min(totalPages,page+1)};renderFacts()" ${page>=totalPages?'disabled':''}>›</button>`;
      html += '</div>';
    }

    g('content').innerHTML = html;
    saveState();
  } catch(e) {
    g('content').innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>加载失败：${esc(e.message)}</div>`;
  }
}

// ===== Selection =====
function toggleSel(id) {
  sel.has(id) ? sel.delete(id) : sel.add(id);
  const cb = document.querySelector(`.fact[data-fid="${id}"] .sel-cb`);
  if (cb) cb.checked = sel.has(id);
  const card = document.querySelector(`.fact[data-fid="${id}"]`);
  if (card) card.classList.toggle('sel', sel.has(id));
  updateBulkBar();
}
function updateBulkBar() {
  g('bcount').textContent = sel.size;
  g('bulkBar').classList.toggle('show', sel.size > 0);
}
function toggleAll() {
  const ids = allFacts.map(f=>f.fact_id).filter(id=>!isNaN(id));
  if (sel.size === ids.length) { sel.clear(); }
  else { ids.forEach(id=>sel.add(id)); }
  renderFacts();
}

// ===== CRUD =====
function openAdd() {
  const o = document.createElement('div'); o.className='modal-overlay';
  o.innerHTML=`<div class="modal"><h3>新增事实</h3>
    <label>内容</label><textarea id="newContent" placeholder="请输入事实内容..."></textarea>
    <label>分类</label>
    <select id="newCat">
      <option value="user_pref">用户偏好</option>
      <option value="project">项目</option>
      <option value="tool">工具</option>
      <option value="general">通用</option>
    </select>
    <label>标签（逗号分隔）</label><input id="newTags" placeholder="例: python, api, config">
    <label>信任度</label><input id="newTrust" type="number" step="0.1" min="0" max="1" value="0.7">
    <div class="mbtns">
      <button class="btn" onclick="closeModal(this)">取消</button>
      <button class="btn btn-primary" onclick="doAdd()">保存</button>
    </div></div>`;
  document.body.appendChild(o);
  trapFocus(o);
  setTimeout(() => enhanceTagInput('newTags'), 100);
}
async function doAdd() {
  const content = g('newContent').value.trim();
  if (!content) { toast('请输入内容','e'); return; }
  try {
    await api('/facts/new', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        content,
        category: g('newCat').value,
        tags: g('newTags').value.trim(),
        trust_score: parseFloat(g('newTrust').value)||0.7
      })
    });
    closeModal(document.querySelector('.modal-overlay'));
    toast('新增成功');
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); }
}
function openEditFrom(btn) {
  const id = btn.dataset.eid;
  const content = btn.dataset.ec;
  const cat = btn.dataset.eca;
  const tags = btn.dataset.etag;
  const trust = btn.dataset.et;
  const o = document.createElement('div'); o.className='modal-overlay';
  o.innerHTML=`<div class="modal"><h3>编辑事实 #${id}</h3>
    <label>内容</label><textarea id="editContent">${esc(content)}</textarea>
    <label>分类</label>
    <select id="editCat">
      ${CAT_LIST.map(c=>`<option value="${c}" ${c===cat?'selected':''}>${CAT_NAMES[c]||c}</option>`).join('')}
    </select>
    <label>标签（逗号分隔）</label><input id="editTags" value="${esc(tags)}">
    <label>信任度</label><input id="editTrust" type="number" step="0.1" min="0" max="1" value="${trust}">
    <div class="mbtns">
      <button class="btn" onclick="closeModal(this)">取消</button>
      <button class="btn btn-primary" onclick="doEdit(${id})">保存</button>
    </div></div>`;
  document.body.appendChild(o);
  trapFocus(o);
  setTimeout(() => enhanceTagInput('editTags'), 100);
}
async function doEdit(id) {
  const content = g('editContent').value.trim();
  if (!content) { toast('内容不能为空','e'); return; }
  try {
    await api(`/facts/${id}/edit`, {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        content,
        category: g('editCat').value,
        tags: g('editTags').value.trim(),
        trust_score: parseFloat(g('editTrust').value)||0.5
      })
    });
    closeModal(document.querySelector('.modal-overlay'));
    toast('编辑成功');
    renderFacts();
  } catch(e) { toast(e.message,'e'); }
}
async function del(id) {
  if (!confirm('确认删除这条事实？')) return;
  try {
    await api('/facts/bulk', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ids:[id], action:'soft_delete'})
    });
    sel.delete(id); updateBulkBar();
    toast('已移至回收站','s', ()=>restoreOne(id));
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); }
}
async function restoreOne(id) {
  try {
    await api(`/facts/${id}/restore`, { method:'POST' });
    toast('已撤销删除');
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); }
}

// ===== Bulk Operations (using /api/facts/bulk) =====
function adjustPageAfterBulk(deletedCount) {
  // If we removed all items on current page, go back one page
  if (deletedCount > 0 && page > 1 && allFacts.length <= deletedCount) {
    page = Math.max(1, page - 1);
  }
}
async function bulkDel() {
  const ids = [...sel];
  if (!ids.length) return;
  if (!confirm(`确认删除 ${ids.length} 条事实？`)) return;
  try {
    await api('/facts/bulk', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ids, action:'soft_delete'})
    });
    adjustPageAfterBulk(ids.length);
    sel.clear(); updateBulkBar();
    toast(`已删除 ${ids.length} 条`);
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); }
}
async function bulkRestore() {
  const ids = [...sel];
  if (!ids.length) return;
  try {
    await api('/facts/bulk', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ids, action:'restore'})
    });
    sel.clear(); updateBulkBar();
    toast(`已恢复 ${ids.length} 条`);
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); }
}
async function bulkHard() {
  const ids = [...sel];
  if (!ids.length) return;
  if (!confirm(`💀 彻底删除 ${ids.length} 条？此操作不可恢复！`)) return;
  try {
    await api('/facts/bulk', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ids, action:'hard_delete'})
    });
    adjustPageAfterBulk(ids.length);
    sel.clear(); updateBulkBar();
    toast(`已彻底删除 ${ids.length} 条`);
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); }
}
function openBulkCat() {
  if (!sel.size) return;
  const o = document.createElement('div'); o.className='modal-overlay';
  o.innerHTML=`<div class="modal"><h3>批量改分类（${sel.size} 条）</h3>
    <div class="cat-picker">
      ${CAT_LIST.map(c=>`<button onclick="doBulkCat('${c}')">${CAT_NAMES[c]}</button>`).join('')}
    </div>
    <div class="mbtns"><button class="btn" onclick="closeModal(this)">取消</button></div></div>`;
  document.body.appendChild(o);
  trapFocus(o);
}
async function doBulkCat(cat) {
  const ids = [...sel];
  try {
    await api('/facts/bulk', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ids, action:'set_category', category:cat})
    });
    closeModal(document.querySelector('.modal-overlay'));
    sel.clear(); updateBulkBar();
    toast(`已更新 ${ids.length} 条分类`);
    renderFacts();
  } catch(e) { toast(e.message,'e'); }
}
function openBulkTags() {
  if (!sel.size) return;
  const o = document.createElement('div'); o.className='modal-overlay';
  o.innerHTML=`<div class="modal"><h3>批量改标签（${sel.size} 条）</h3>
    <label>新标签（逗号分隔，会替换原有标签）</label>
    <input id="bulkTagsInput" placeholder="例: important, reviewed, todo">
    <div class="mbtns">
      <button class="btn" onclick="closeModal(this)">取消</button>
      <button class="btn btn-primary" onclick="doBulkTags()">保存</button>
    </div></div>`;
  document.body.appendChild(o);
  trapFocus(o);
}
async function doBulkTags() {
  const ids = [...sel];
  const tags = g('bulkTagsInput').value.trim();
  try {
    await api('/facts/bulk', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ids, action:'set_tags', tags})
    });
    closeModal(document.querySelector('.modal-overlay'));
    sel.clear(); updateBulkBar();
    toast(`已更新 ${ids.length} 条标签`);
    renderFacts();
  } catch(e) { toast(e.message,'e'); }
}

// ===== Entities =====
async function renderEntities() {
  g('content').innerHTML = skeletonCards(5);
  try {
    const d = await api('/entities');
    const entities = d.entities || d.data || d;
    if (!entities.length) {
      g('content').innerHTML = '<div class=\"empty\"><div class=\"empty-icon\">🏷️</div>没有找到实体</div>';
      return;
    }
    let html = '<div class="entity-list">';
    entities.forEach(e => {
      const name = e.entity || e.name || 'Unknown';
      const cnt = e.fact_count || e.count || 0;
      html += `<div class="entity-item" onclick="showEntity('${esc(name)}')">
        <div class="ename">🏷️ ${esc(name)}</div>
        <div class="ecount">${cnt} 条关联事实</div>
      </div>`;
    });
    html += '</div>';
    g('content').innerHTML = html;
  } catch(e) {
    g('content').innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>加载失败：${esc(e.message)}</div>`;
  }
}
async function showEntity(name) {
  try {
    const d = await api(`/entities/${encodeURIComponent(name)}?by=name`);
    const e = d.entity || d;
    const facts = e.facts || e.associated_facts || [];
    let html = `<div class="edetail">
      <h3>🏷️ ${esc(name)}</h3>
      <div class="esub">${facts.length} 条关联事实</div>
      <div class="efacts">`;
    facts.forEach(f => {
      const dt = (f.created_at||'').replace(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}).*/,'$2-$3 $4:$5');
      html += `<div class="efact">
        <div>${esc(f.content)}</div>
        <div class="emeta">信任 ${(f.trust_score*100).toFixed(0)}% · ${dt}</div>
      </div>`;
    });
    html += `</div></div>
      <button class="btn" onclick="renderEntities()">← 返回实体列表</button>`;
    g('content').innerHTML = html;
  } catch(e) { toast(e.message,'e'); }
}

// ===== Sessions =====
async function renderSessions() {
  if (viewingSession) { renderChat(); return; }
  g('content').innerHTML = skeletonCards(5);
  try {
    const d = await api('/sessions');
    const sessions = d.sessions || d.data || d;
    if (!sessions.length) {
      g('content').innerHTML = '<div class=\"empty\"><div class=\"empty-icon\">💬</div>没有找到对话</div>';
      return;
    }
    let html = '<div class="session-list">';
    sessions.forEach(s => {
      const title = s.title || s.name || '对话';
      const msgs = s.msgs || s.msg_count || s.total_messages || s.message_count || 0;
      const date = s.date ? s.date.slice(0,16) : '';
      // Compact size display
      const sz = s.size || '';
      // Time ago
      let timeAgo = '';
      if (s.date) {
        try {
          const dt = new Date(s.date.replace(' ','T')+'+08:00');
          const now = new Date();
          const diff = (now - dt) / 1000;
          if (diff < 60) timeAgo = '刚刚';
          else if (diff < 3600) timeAgo = Math.floor(diff/60) + '分钟前';
          else if (diff < 86400) timeAgo = Math.floor(diff/3600) + '小时前';
          else if (diff < 2592000) timeAgo = Math.floor(diff/86400) + '天前';
          else timeAgo = date.slice(5);
        } catch(e) { timeAgo = date.slice(5); }
      }
      html += `<div class="session-card" onclick="openSession('${s.id||s.session_id}')">
        <div class="sname">💬 ${esc(title)}</div>
        <div class="sinfo">
          <span>${msgs} 条</span>
          ${sz ? `<span>${sz}</span>` : ''}
          ${timeAgo ? `<span class="s-time">${timeAgo}</span>` : ''}
          ${date ? `<span class="s-date">${date}</span>` : ''}
        </div>
      </div>`;
    });
    html += '</div>';
    g('content').innerHTML = html;
  } catch(e) {
    g('content').innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>加载失败：${esc(e.message)}</div>`;
  }
}
function openSession(id) {
  viewingSession = id;
  saveState();
  renderSessions();
}
async function renderChat() {
  g('content').innerHTML = skeletonCards(5);
  try {
    const d = await api(`/sessions/${viewingSession}`);
    const msgs = d.messages || d.data || [];
    const firstUser = msgs.find(m=>m.role==='user');
    const title = firstUser ? (firstUser.content||'').slice(0,120) : '对话详情';
    const msgCount = msgs.filter(m=>m.role==='user'||m.role==='assistant').length;

    let html = '<div class="chat-view">';
    html += `<div class="chat-top">
      <button class="ct-back" onclick="viewingSession=null;saveState();renderSessions()">←</button>
      <span class="ct-title">${esc(title)}</span>
      <span class="ct-count">${msgCount} 条</span>
    </div>
    <div id="chatSearchWrap" style="margin-bottom:10px;position:relative">
      <span style="position:absolute;left:10px;top:50%;transform:translateY(-50%);color:var(--text2);font-size:13px">🔍</span>
      <input placeholder="搜索对话内容..." oninput="filterChat(this)" style="width:100%;padding:8px 12px 8px 32px;border:1px solid var(--border);border-radius:8px;font-size:13px;font-family:var(--font);background:var(--card);color:var(--text);outline:none">
    </div>
    <div class="chat-msgs">`;

    msgs.forEach(m => {
      if (m.role === 'tool') return;
      const txt = (m.content || '').trim();
      if (!txt) return;
      // 跳过系统内部消息（上下文压缩提示、思考过程等）
      if (txt.startsWith('[CONTEXT COMPACTION') || txt.startsWith('[SYSTEM') ) return;
      // Format timestamp
      const ts = m.timestamp || m.created_at || '';
      const timeStr = ts ? ts.slice(11,16) : '';
      if (m.role === 'assistant') {
        html += `<div class="msg assistant">
          <div class="md">${renderMD(txt)}</div>
          ${timeStr ? `<div class="msg-time">${timeStr}</div>` : ''}
        </div>`;
      } else {
        html += `<div class="msg user">
          <div>${esc(txt)}</div>
          ${timeStr ? `<div class="msg-time user-time">${timeStr}</div>` : ''}
        </div>`;
      }
    });
    html += '</div></div>';
    g('content').innerHTML = html;
  } catch(e) {
    viewingSession = null;
    saveState();
    g('content').innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>加载失败：${esc(e.message)}</div>`;
  }
}

// ===== Export =====
async function exportJSON() {
  try {
    const d = await api('/facts/export');
    const blob = new Blob([JSON.stringify(d,null,2)], {type:'application/json'});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `hermes-memory-${new Date().toISOString().slice(0,10)}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
    toast('导出成功');
  } catch(e) { toast(e.message,'e'); }
}

// ===== Import =====
async function importJSON(input) {
  const file = input.files[0];
  if (!file) return;
  try {
    const text = await file.text();
    const data = JSON.parse(text);
    if (!data.facts || !data.facts.length) { toast('无效的备份文件','e'); return; }
    const result = await api('/facts/import', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({facts: data.facts})
    });
    toast(`导入成功：${result.imported} 条${result.skipped ? `，跳过 ${result.skipped} 条` : ''}`);
    input.value = '';
    renderFacts(); renderStats();
  } catch(e) { toast(e.message,'e'); input.value = ''; }
}

// ===== Detail Modal =====
async function showDetail(factId) {
  try {
    const d = await api(`/facts/${factId}`);
    const f = d.fact || d;
    const cc = f.category || 'general';
    const catName = CAT_NAMES[cc] || cc;
    const tpct = (f.trust_score*100).toFixed(0);
    const dt = (f.created_at||'').replace(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}).*/,'$1-$2-$3 $4:$5');
    const ut = (f.updated_at||'').replace(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}).*/,'$1-$2-$3 $4:$5');
    const entities = (f.entities||[]).map(e => esc(e.name||'')).join(', ');
    const tags = (f.tags||'').replace(/,/g, ', ');
    const ret = f.retrieval_count || 0;
    const helpful = f.helpful_count || 0;
    const o = document.createElement('div'); o.className='modal-overlay';
    o.innerHTML=`<div class="modal" style="max-width:640px">
      <h3>📄 事实 #${f.fact_id}</h3>
      <div style="font-size:14px;line-height:1.8;margin-bottom:16px;word-break:break-word">${esc(f.content)}</div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;font-size:12px;color:var(--text2)">
        <div><strong>分类：</strong><span class="tag ${cc}">${catName}</span></div>
        <div><strong>信任度：</strong>${tpct}%</div>
        <div><strong>创建时间：</strong>${dt}</div>
        <div><strong>更新时间：</strong>${ut}</div>
        ${tags ? `<div style="grid-column:1/-1"><strong>标签：</strong>${tags}</div>` : ''}
        ${entities ? `<div style="grid-column:1/-1"><strong>实体：</strong>${entities}</div>` : ''}
        <div><strong>检索次数：</strong>${ret}</div>
        <div><strong>有帮助：</strong>${helpful}次</div>
      </div>
      <div class="mbtns">
        <button class="btn btn-primary" onclick="closeModal(this)">关闭</button>
      </div>
    </div>`;
    document.body.appendChild(o);
    trapFocus(o);
  } catch(e) { toast(e.message,'e'); }
}

// ===== Tag Autocomplete =====
let cachedTags = null;
async function getTags() {
  if (!cachedTags) {
    try {
      const d = await api('/tags');
      cachedTags = d.tags || [];
    } catch(e) { cachedTags = []; }
  }
  return cachedTags;
}

function enhanceTagInput(inputId) {
  const input = document.getElementById(inputId);
  if (!input) return;
  const wrap = document.createElement('div');
  wrap.style.cssText = 'position:relative;margin-bottom:14px';
  input.parentNode.insertBefore(wrap, input);
  wrap.appendChild(input);
  const dl = document.createElement('div');
  dl.style.cssText = 'position:absolute;top:100%;left:0;right:0;z-index:50;background:var(--card);border:1px solid var(--border);border-radius:0 0 8px 8px;max-height:160px;overflow-y:auto;display:none;font-size:13px';
  wrap.appendChild(dl);
  let hideTimer;
  input.addEventListener('focus', async () => {
    const tags = await getTags();
    const val = input.value;
    const existing = new Set(val.split(',').map(t=>t.trim()).filter(Boolean));
    const filtered = tags.filter(t => !existing.has(t) && (!val || t.includes(val)));
    if (!filtered.length) { dl.style.display = 'none'; return; }
    dl.innerHTML = filtered.map(t => `<div style="padding:6px 10px;cursor:pointer;transition:background .1s;color:var(--text)" onmouseover="this.style.background='var(--brand-light)'" onmouseout="this.style.background=''" onclick="addTagToInput('${inputId}','${esc(t)}')">#${esc(t)}</div>`).join('');
    dl.style.display = 'block';
  });
  input.addEventListener('blur', () => { hideTimer = setTimeout(() => { dl.style.display = 'none'; }, 200); });
  input.addEventListener('input', () => { if (dl.style.display === 'block') input.dispatchEvent(new Event('focus')); });
}

function addTagToInput(inputId, tag) {
  const input = document.getElementById(inputId);
  if (!input) return;
  const existing = input.value.split(',').map(t=>t.trim()).filter(Boolean);
  if (!existing.includes(tag)) {
    existing.push(tag);
    input.value = existing.join(', ');
  }
  input.focus();
}

// ===== Chat Search =====
function filterChat(input) {
  const q = input.value.trim().toLowerCase();
  document.querySelectorAll('.chat-msgs .msg').forEach(el => {
    const text = el.textContent.toLowerCase();
    el.style.display = (!q || text.includes(q)) ? '' : 'none';
  });
}

// ===== Bulk Add/Remove Tags =====
function openBulkAddTags() {
  if (!sel.size) return;
  const o = document.createElement('div'); o.className='modal-overlay';
  o.innerHTML=`<div class="modal"><h3>批量添加标签（${sel.size} 条）</h3>
    <label>要添加的标签（逗号分隔，不会覆盖现有标签）</label>
    <input id="bulkAddTagsInput" placeholder="例: important, reviewed">
    <div class="mbtns">
      <button class="btn" onclick="closeModal(this)">取消</button>
      <button class="btn btn-primary" onclick="doBulkAddTags()">保存</button>
    </div></div>`;
  document.body.appendChild(o);
  trapFocus(o);
}
async function doBulkAddTags() {
  const ids = [...sel];
  const tags = g('bulkAddTagsInput').value.trim();
  if (!tags) { toast('请输入标签','e'); return; }
  try {
    await api('/facts/bulk', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ids, action:'add_tags', tags}) });
    closeModal(document.querySelector('.modal-overlay'));
    sel.clear(); updateBulkBar();
    toast(`已添加标签到 ${ids.length} 条`);
    renderFacts();
  } catch(e) { toast(e.message,'e'); }
}
function openBulkRemoveTags() {
  if (!sel.size) return;
  const o = document.createElement('div'); o.className='modal-overlay';
  o.innerHTML=`<div class="modal"><h3>批量移除标签（${sel.size} 条）</h3>
    <label>要移除的标签（逗号分隔）</label>
    <input id="bulkRemoveTagsInput" placeholder="例: temp, draft">
    <div class="mbtns">
      <button class="btn" onclick="closeModal(this)">取消</button>
      <button class="btn btn-danger" onclick="doBulkRemoveTags()">移除</button>
    </div></div>`;
  document.body.appendChild(o);
  trapFocus(o);
}
async function doBulkRemoveTags() {
  const ids = [...sel];
  const tags = g('bulkRemoveTagsInput').value.trim();
  if (!tags) { toast('请输入标签','e'); return; }
  try {
    await api('/facts/bulk', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ids, action:'remove_tags', tags}) });
    closeModal(document.querySelector('.modal-overlay'));
    sel.clear(); updateBulkBar();
    toast(`已从 ${ids.length} 条移除标签`);
    renderFacts();
  } catch(e) { toast(e.message,'e'); }
}

// ===== Search =====
let searchTimer;
function onSearch() { clearTimeout(searchTimer); searchTimer=setTimeout(()=>{page=1;renderFacts();saveState();},250); }

// ===== Skills =====
let skillsData = null;

function renderMD(text) {
  if (!text) return '';
  // Use marked.js (loaded from CDN) for proper Markdown rendering
  if (typeof marked !== 'undefined') {
    // Configure safe defaults
    marked.setOptions({
      breaks: true,
      gfm: true,
    });
    return marked.parse(text);
  }
  // Fallback: basic HTML escaping only
  return String(text).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

async function renderSkills() {
  g('content').innerHTML = skeletonCards(5);
  try {
    if (!skillsData) {
      const d = await api('/skills');
      skillsData = d.skills || [];
    }
    const skills = skillsData.filter(s => s.installed);
    if (!skills.length) {
      g('content').innerHTML = '<div class=\"empty\"><div class=\"empty-icon\">🔧</div>没有自己安装的技能</div>';
      return;
    }
    const groups = {};
    skills.forEach(s => {
      const cat = s.category || 'other';
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(s);
    });
    const catOrder = Object.keys(groups).sort();
    let html = `<div style="font-size:12px;color:var(--text2);margin-bottom:12px">共 ${skills.length} 个技能</div>`;
    catOrder.forEach(cat => {
      html += `<h3 style="font-size:14px;font-weight:600;color:var(--text);margin:20px 0 10px">${esc(cat)}</h3>
      <div class="session-list">`;
      groups[cat].forEach(s => {
        // Extract first meaningful line from body for preview
        const bodyFirstLine = (s.body||'').replace(/^---[\s\S]*?---\n*/,'').split('\n').filter(l => l.trim() && !l.startsWith('|') && !l.startsWith('`'))[0] || '';
        html += `<div class="session-card" onclick="viewSkill('${esc(s.name||s.dir)}')">
          <div class="sname">🔧 ${esc(s.name||s.dir)}</div>
          <div class="sinfo">${bodyFirstLine ? esc(bodyFirstLine.slice(0,80)) : esc((s.description||'').slice(0,80))}</div>
        </div>`;
      });
      html += '</div>';
    });
    g('content').innerHTML = html;
  } catch(e) {
    g('content').innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>加载失败：${esc(e.message)}</div>`;
  }
}

async function viewSkill(name) {
  viewingSkill = name;
  saveState();
  const cached = (skillsData||[]).find(s => (s.name||s.dir) === name);
  if (!cached) { g('content').innerHTML = '<div class="empty">未找到技能</div>'; return; }
  const body = (cached.body||'');
  // Fetch full detail (includes linked_files)
  const detail = await api(`/skills/${encodeURIComponent(name)}`);
  const linkedFiles = detail.linked_files || {};
  // Strip YAML frontmatter
  const mdBody = body.replace(/^---[\s\S]*?---\n*/,'');
  const desc = cached.description || '';
  let html = `<div style="margin-bottom:16px">
    <button class="btn" onclick="renderSkills()" style="margin-bottom:12px">← 返回列表</button>
    <div class="edetail" style="padding:24px 28px">
      <h2 style="font-size:20px;font-weight:700;margin-bottom:4px">🔧 ${esc(cached.name||name)}</h2>
      ${desc ? `<div style="font-size:13px;color:var(--text2);margin-bottom:16px">${esc(desc)}</div>` : ''}
      <div class="skill-content" style="font-size:14px;line-height:1.8;color:var(--text)">${renderMD(mdBody)}</div>`;

  // Linked files section
  const fileTypes = Object.keys(linkedFiles);
  if (fileTypes.length > 0) {
    const icons = {references:'📖', scripts:'⚙️', templates:'📋', assets:'🎨'};
    html += `<hr style="border:none;border-top:1px solid var(--border);margin:20px 0">
      <h3 style="font-size:15px;font-weight:600;margin-bottom:12px">📎 关联文件</h3>`;
    fileTypes.forEach(type => {
      const files = linkedFiles[type];
      const icon = icons[type] || '📄';
      html += `<div style="margin-bottom:10px">
        <div style="font-size:13px;font-weight:600;color:var(--text2);margin-bottom:4px">${icon} ${type} (${files.length})</div>`;
      files.forEach(f => {
        const fname = f.split('/').pop();
        const fpath = f.split('/').slice(1).join('/') || fname;
        html += `<div class="linked-file" onclick="viewSkillFile('${esc(name)}','${esc(f)}')"
          style="padding:4px 8px;border-radius:4px;cursor:pointer;font-size:13px;color:var(--accent);display:inline-block;margin:2px"
          onmouseover="this.style.background='var(--hover)'" onmouseout="this.style.background='transparent'">
          📄 ${esc(fpath)}</div>`;
      });
      html += `</div>`;
    });
  }

  html += `</div></div>`;
  g('content').innerHTML = html;
}

async function viewSkillFile(skillName, filePath) {
  g('content').innerHTML = skeletonCards(3);
  try {
    const d = await api(`/skills/${encodeURIComponent(skillName)}/file?path=${encodeURIComponent(filePath)}`);
    let html = `<div style="margin-bottom:16px">
      <button class="btn" onclick="viewSkill('${esc(skillName)}')" style="margin-bottom:12px">← 返回技能</button>
      <div class="edetail" style="padding:20px 24px">
        <h3 style="font-size:16px;font-weight:600;margin-bottom:12px">📄 ${esc(d.name)}</h3>`;
    // Check if it's markdown
    if (d.name.endsWith('.md')) {
      html += `<div style="font-size:14px;line-height:1.8;color:var(--text)">${renderMD(d.content)}</div>`;
    } else {
      html += `<pre style="font-size:13px;line-height:1.5;overflow:auto;max-height:70vh;background:var(--card);padding:16px;border-radius:8px;border:1px solid var(--border)">${esc(d.content)}</pre>`;
    }
    html += `</div></div>`;
    g('content').innerHTML = html;
  } catch(e) {
    g('content').innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>加载失败：${esc(e.message)}</div>`;
  }
}

// ===== Keyboard Shortcuts =====
document.addEventListener('keydown', e => {
  // Don't trigger when typing in an input
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;

  switch (e.key) {
    case '/':
      e.preventDefault();
      const searchInput = g('search');
      if (searchInput) { searchInput.focus(); searchInput.select(); }
      break;
    case 'n':
    case 'N':
      e.preventDefault();
      openAdd();
      break;
    case 'j':
    case 'J':
      e.preventDefault();
      // Select next fact card
      const facts = document.querySelectorAll('.fact-list .fact');
      const idx = Array.from(facts).findIndex(c => c.classList.contains('sel'));
      const nextIdx = Math.min(idx + 1, facts.length - 1);
      if (nextIdx >= 0) {
        const id = facts[nextIdx].dataset.fid;
        if (id && !isNaN(id)) { sel.clear(); sel.add(parseInt(id)); renderFacts(); }
      }
      break;
    case 'k':
    case 'K':
      e.preventDefault();
      // Select previous fact card
      const factsK = document.querySelectorAll('.fact-list .fact');
      const idxK = Array.from(factsK).findIndex(c => c.classList.contains('sel'));
      const prevIdx = Math.max(idxK - 1, 0);
      if (factsK.length > 0) {
        const id = factsK[prevIdx].dataset.fid;
        if (id && !isNaN(id)) { sel.clear(); sel.add(parseInt(id)); renderFacts(); }
      }
      break;
    case 'a':
    case 'A':
      e.preventDefault();
      if (currentTab === 'facts') toggleAll();
      break;
    case 'r':
    case 'R':
      e.preventDefault();
      if (sel.size) bulkRestore();
      break;
    case 'Delete':
    case 'Backspace':
      e.preventDefault();
      if (sel.size) bulkDel();
      break;
    case 'Escape':
      const overlay = document.querySelector('.modal-overlay');
      if (overlay) overlay.remove();
      break;
  }
});

// ===== Init =====
document.addEventListener('DOMContentLoaded', async () => {
  loadState();
  await renderStats();
  // Set toolbar visibility based on restored tab
  g('toolbar').style.display = currentTab==='facts' ? 'flex' : 'none';
  if (currentTab==='facts') renderFacts();
  else if (currentTab==='entities') renderEntities();
  else if (currentTab==='skills') {
    if (viewingSkill) { await renderSkills(); viewSkill(viewingSkill); }
    else renderSkills();
  }
  else renderSessions();
});

// ===== Keyboard hint helper =====
function updateKbdHint() {
  let hint = document.querySelector('.kbd-hint');
  if (!hint) {
    hint = document.createElement('div');
    hint.className = 'kbd-hint';
    document.body.appendChild(hint);
  }
  hint.innerHTML = `<kbd>/</kbd> 搜索 <kbd>N</kbd> 新增 <kbd>J</kbd><kbd>K</kbd> 选中 <kbd>A</kbd> 全选 <kbd>Del</kbd> 删除 <kbd>R</kbd> 恢复 <kbd>Esc</kbd> 关闭`;
}
updateKbdHint();
</script>
</body>
</html>

"""

if __name__ == "__main__":
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8643
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")
