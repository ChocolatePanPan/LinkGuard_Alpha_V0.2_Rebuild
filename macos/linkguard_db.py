"""
linkguard_db.py — LinkGuard 統一資料庫模組
管理所有數據寫入，使用 SQLite WAL 模式
資料庫路徑: ./data/linkguard.db
"""

from __future__ import annotations

import os
import sqlite3
import traceback
from datetime import datetime, timezone, timedelta
from utils import now_iso, TZ_TW

# === 設定 ===
DB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
DB_PATH = os.path.join(DB_DIR, "linkguard.db")



def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _ensure_column(conn: sqlite3.Connection, table: str, column: str, definition: str):
    existing = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in existing:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


# ============================================================
# 初始化
# ============================================================

def init_db():
    """建立資料庫目錄、啟用 WAL 模式、建立 8 張資料表"""
    os.makedirs(DB_DIR, exist_ok=True)
    conn = _get_conn()
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS decisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            voice_text TEXT,
            patients_summary TEXT,
            weather_summary TEXT,
            decision_text TEXT,
            trigger_type TEXT
        );

        CREATE TABLE IF NOT EXISTS patients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id TEXT UNIQUE,
            timestamp TEXT,
            device_id TEXT,
            breathing_rate INTEGER,
            capillary_refill REAL,
            can_follow_commands INTEGER,
            location_desc TEXT,
            location_lat REAL,
            location_lon REAL,
            priority TEXT,
            reason TEXT,
            start_bonus REAL DEFAULT 0,
            total_score REAL DEFAULT 0,
            dimension_data TEXT DEFAULT '{}',
            status TEXT DEFAULT 'active',
            notes TEXT,
            updated_at TEXT
        );

        CREATE TABLE IF NOT EXISTS locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            device_id TEXT,
            name TEXT,
            role TEXT,
            lat REAL,
            lon REAL,
            accuracy REAL
        );

        CREATE TABLE IF NOT EXISTS reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            report_id TEXT UNIQUE,
            timestamp TEXT,
            sender_id TEXT,
            sender_name TEXT,
            audio_path TEXT,
            transcription TEXT,
            location_lat REAL,
            location_lon REAL,
            location_desc TEXT,
            patients_snapshot TEXT,
            weather_snapshot TEXT
        );

        CREATE TABLE IF NOT EXISTS weather_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            station_id TEXT,
            temperature REAL,
            humidity REAL,
            wind_speed REAL,
            rainfall REAL,
            obs_time TEXT
        );

        CREATE TABLE IF NOT EXISTS transcriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            sender_id TEXT,
            text TEXT,
            source TEXT,
            duration REAL,
            report_id TEXT
        );

        CREATE TABLE IF NOT EXISTS node_status_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            node_id TEXT,
            rssi INTEGER,
            snr REAL,
            battery REAL,
            lat REAL,
            lon REAL,
            pdr REAL,
            online INTEGER
        );

        CREATE TABLE IF NOT EXISTS system_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            event_type TEXT,
            device_id TEXT,
            description TEXT,
            severity TEXT
        );

        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            photo_id TEXT UNIQUE,
            timestamp TEXT,
            sender_id TEXT,
            sender_name TEXT,
            photo_path TEXT,
            lat REAL,
            lon REAL,
            location_desc TEXT,
            caption TEXT
        );

        CREATE TABLE IF NOT EXISTS resources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resource_id TEXT UNIQUE,
            type TEXT,
            name TEXT,
            total INTEGER DEFAULT 1,
            available INTEGER DEFAULT 1,
            location_desc TEXT,
            assigned_to TEXT,
            assigned_zone TEXT DEFAULT '',
            status TEXT DEFAULT 'available',
            updated_at TEXT
        );

        CREATE TABLE IF NOT EXISTS resource_allocations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resource_id TEXT,
            assigned_zone TEXT,
            assigned_to TEXT,
            quantity INTEGER DEFAULT 1,
            location_desc TEXT,
            updated_at TEXT,
            UNIQUE(resource_id, assigned_zone)
        );

        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            device_id TEXT,
            sender_name TEXT,
            content TEXT
        );

        CREATE TABLE IF NOT EXISTS status_reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            device_id TEXT,
            battery INTEGER,
            ble_connected INTEGER,
            data_json TEXT
        );

        CREATE TABLE IF NOT EXISTS delivery_tracking (
            msg_id TEXT PRIMARY KEY,
            msg_type TEXT,
            target_devices TEXT,
            delivered_devices TEXT DEFAULT '[]',
            created_at TEXT,
            ttl_seconds INTEGER DEFAULT 300
        );

        CREATE TABLE IF NOT EXISTS nicknames (
            device_id TEXT PRIMARY KEY,
            nickname TEXT NOT NULL,
            role TEXT,
            updated_at TEXT
        );
    """)
    # 建立常用查詢索引
    conn.executescript("""
        CREATE INDEX IF NOT EXISTS idx_reports_report_id ON reports(report_id);
        CREATE INDEX IF NOT EXISTS idx_reports_timestamp ON reports(timestamp);
        CREATE INDEX IF NOT EXISTS idx_photos_photo_id ON photos(photo_id);
        CREATE INDEX IF NOT EXISTS idx_photos_timestamp ON photos(timestamp);
        CREATE INDEX IF NOT EXISTS idx_patients_patient_id ON patients(patient_id);
        CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp);
        CREATE INDEX IF NOT EXISTS idx_locations_device_id ON locations(device_id);
        CREATE INDEX IF NOT EXISTS idx_node_status_log_timestamp ON node_status_log(timestamp);
    """)
    conn.commit()
    conn.close()
    print(f"[DB] 資料庫已初始化: {DB_PATH}")


# ============================================================
# 寫入函式
# ============================================================

def save_decision(voice_text: str, patients_summary: str,
                  weather_summary: str, decision_text: str,
                  trigger_type: str = "manual"):
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO decisions (timestamp, voice_text, patients_summary, "
            "weather_summary, decision_text, trigger_type) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (now_iso(), voice_text, patients_summary,
             weather_summary, decision_text, trigger_type),
        )
        conn.commit()
    _ensure_column(conn, "resources", "assigned_zone", "TEXT DEFAULT ''")
    except Exception as e:
        log_event("error", "db", f"save_decision 失敗: {e}", "error")
    finally:
        conn.close()


def save_patient(patient_dict: dict):
    conn = _get_conn()
    try:
        ts = now_iso()
        p = patient_dict
        conn.execute(
            """INSERT INTO patients
               (patient_id, timestamp, device_id, breathing_rate,
                capillary_refill, can_follow_commands, location_desc,
                location_lat, location_lon, priority, reason,
                start_bonus, total_score, dimension_data, status,
                notes, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(patient_id) DO UPDATE SET
                 timestamp=excluded.timestamp,
                 device_id=excluded.device_id,
                 breathing_rate=excluded.breathing_rate,
                 capillary_refill=excluded.capillary_refill,
                 can_follow_commands=excluded.can_follow_commands,
                 location_desc=excluded.location_desc,
                 location_lat=excluded.location_lat,
                 location_lon=excluded.location_lon,
                 priority=excluded.priority,
                 reason=excluded.reason,
                 start_bonus=excluded.start_bonus,
                 total_score=excluded.total_score,
                 dimension_data=excluded.dimension_data,
                 status=excluded.status,
                 notes=excluded.notes,
                 updated_at=excluded.updated_at
            """,
            (
                p.get("patient_id", p.get("id", "")),
                ts,
                p.get("device_id", ""),
                p.get("breathing_rate"),
                p.get("capillary_refill"),
                int(p.get("can_follow_commands", 0)) if p.get("can_follow_commands") is not None else None,
                p.get("location_desc", p.get("location", "")),
                p.get("location_lat"),
                p.get("location_lon"),
                p.get("priority", ""),
                p.get("reason", ""),
                p.get("start_bonus", 0),
                p.get("total_score", 0),
                p.get("dimension_data", "{}"),
                p.get("status", "active"),
                p.get("notes", ""),
                ts,
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_patient 失敗: {e}", "error")
    finally:
        conn.close()


def save_location(device_id: str, name: str, role: str,
                  lat: float, lon: float, accuracy: float = 0.0):
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO locations (timestamp, device_id, name, role, lat, lon, accuracy) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (now_iso(), device_id, name, role, lat, lon, accuracy),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_location 失敗: {e}", "error")
    finally:
        conn.close()


def save_report(report_dict: dict):
    conn = _get_conn()
    try:
        r = report_dict
        conn.execute(
            """INSERT INTO reports
               (report_id, timestamp, sender_id, sender_name, audio_path,
                transcription, location_lat, location_lon, location_desc,
                patients_snapshot, weather_snapshot)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                r.get("report_id", ""),
                r.get("timestamp", now_iso()),
                r.get("sender_id", ""),
                r.get("sender_name", ""),
                r.get("audio_path", ""),
                r.get("transcription", ""),
                r.get("location_lat"),
                r.get("location_lon"),
                r.get("location_desc", ""),
                r.get("patients_snapshot", "[]"),
                r.get("weather_snapshot", "{}"),
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_report 失敗: {e}", "error")
    finally:
        conn.close()


def save_weather(weather_dict: dict):
    conn = _get_conn()
    try:
        w = weather_dict
        conn.execute(
            "INSERT INTO weather_log (timestamp, station_id, temperature, "
            "humidity, wind_speed, rainfall, obs_time) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                now_iso(),
                w.get("station_id", ""),
                w.get("temperature"),
                w.get("humidity"),
                w.get("wind_speed"),
                w.get("rainfall"),
                w.get("obs_time", w.get("timestamp", "")),
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_weather 失敗: {e}", "error")
    finally:
        conn.close()


def save_transcription(sender_id: str, text: str, source: str,
                       duration: float = 0.0, report_id: str = None):
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO transcriptions (timestamp, sender_id, text, source, duration, report_id) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (now_iso(), sender_id, text, source, duration, report_id),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_transcription 失敗: {e}", "error")
    finally:
        conn.close()


# ============================================================
# 暱稱 (device_id ↔ nickname)
# ============================================================
def set_nickname(device_id: str, nickname: str, role: str = "") -> bool:
    """設定/更新指定 device_id 的暱稱。"""
    if not device_id or not nickname:
        return False
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO nicknames (device_id, nickname, role, updated_at) "
            "VALUES (?, ?, ?, ?) "
            "ON CONFLICT(device_id) DO UPDATE SET "
            "nickname=excluded.nickname, role=excluded.role, updated_at=excluded.updated_at",
            (device_id, nickname, role, now_iso()),
        )
        conn.commit()
        return True
    except Exception as e:
        log_event("error", "db", f"set_nickname 失敗: {e}", "error")
        return False
    finally:
        conn.close()


def get_nickname(device_id: str) -> dict | None:
    if not device_id:
        return None
    conn = _get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM nicknames WHERE device_id = ?", (device_id,)
        ).fetchone()
        return dict(row) if row else None
    except Exception as e:
        log_event("error", "db", f"get_nickname 失敗: {e}", "error")
        return None
    finally:
        conn.close()


def get_all_nicknames() -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM nicknames ORDER BY updated_at DESC"
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_all_nicknames 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def delete_nickname(device_id: str) -> bool:
    if not device_id:
        return False
    conn = _get_conn()
    try:
        conn.execute("DELETE FROM nicknames WHERE device_id = ?", (device_id,))
        conn.commit()
        return True
    except Exception as e:
        log_event("error", "db", f"delete_nickname 失敗: {e}", "error")
        return False
    finally:
        conn.close()


def save_node_status(node_dict: dict):
    conn = _get_conn()
    try:
        n = node_dict
        loc = n.get("location", {})
        conn.execute(
            "INSERT INTO node_status_log "
            "(timestamp, node_id, rssi, snr, battery, lat, lon, pdr, online) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                now_iso(),
                n.get("node_id", ""),
                n.get("rssi"),
                n.get("snr"),
                n.get("battery"),
                loc.get("lat") if isinstance(loc, dict) else n.get("lat"),
                loc.get("lon") if isinstance(loc, dict) else n.get("lon"),
                n.get("pdr"),
                1 if n.get("online", True) else 0,
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_node_status 失敗: {e}", "error")
    finally:
        conn.close()


def log_event(event_type: str, device_id: str, description: str,
              severity: str = "info"):
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO system_events (timestamp, event_type, device_id, description, severity) "
            "VALUES (?, ?, ?, ?, ?)",
            (now_iso(), event_type, device_id, description, severity),
        )
        conn.commit()
    except Exception:
        # 避免遞迴 — fallback 到 print
        print(f"[DB-ERROR] log_event 失敗: {traceback.format_exc()}")
    finally:
        conn.close()


# --- Mac HQ 轉發資料 ---

def save_status_report(device_id: str, data: dict):
    """儲存前線裝置狀態報告（經 Mac HQ 轉發）"""
    import json as _json
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO status_reports (timestamp, device_id, battery, ble_connected, data_json) "
            "VALUES (?, ?, ?, ?, ?)",
            (
                now_iso(),
                device_id,
                data.get("battery", 0),
                1 if data.get("bleConnected") else 0,
                _json.dumps(data, ensure_ascii=False),
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_status_report 失敗: {e}", "error")
    finally:
        conn.close()


def save_chat(device_id: str, sender_name: str, content: str):
    """儲存聊天訊息（經 Mac HQ 轉發）"""
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO chats (timestamp, device_id, sender_name, content) "
            "VALUES (?, ?, ?, ?)",
            (now_iso(), device_id, sender_name, content),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_chat 失敗: {e}", "error")
    finally:
        conn.close()


def save_event(event_type: str, device_id: str, data: dict):
    """通用事件儲存（危險回報、增援、SOS 等經 Mac HQ 轉發的事件）"""
    import json as _json
    description = _json.dumps(data, ensure_ascii=False)[:500]
    log_event(event_type, device_id, description, "info")


# --- Photos ---

def save_photo(photo_dict: dict):
    conn = _get_conn()
    try:
        p = photo_dict
        conn.execute(
            """INSERT INTO photos
               (photo_id, timestamp, sender_id, sender_name,
                photo_path, lat, lon, location_desc, caption)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                p.get("photo_id", ""),
                p.get("timestamp", now_iso()),
                p.get("sender_id", ""),
                p.get("sender_name", ""),
                p.get("photo_path", ""),
                p.get("lat"),
                p.get("lon"),
                p.get("location_desc", ""),
                p.get("caption", ""),
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_photo 失敗: {e}", "error")
    finally:
        conn.close()


def get_photos(limit: int = 20) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM photos ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_photos 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_photo(photo_id: str) -> dict | None:
    conn = _get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM photos WHERE photo_id = ?", (photo_id,)
        ).fetchone()
        return dict(row) if row else None
    except Exception as e:
        log_event("error", "db", f"get_photo 失敗: {e}", "error")
        return None
    finally:
        conn.close()


# --- Resources ---

def save_resource(resource_dict: dict):
    conn = _get_conn()
    try:
        r = resource_dict
        conn.execute(
            """INSERT INTO resources
               (resource_id, type, name, total, available,
                                location_desc, assigned_to, assigned_zone, status, updated_at)
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(resource_id) DO UPDATE SET
                 type=excluded.type, name=excluded.name,
                 total=excluded.total, available=excluded.available,
                 location_desc=excluded.location_desc,
                 assigned_to=excluded.assigned_to,
                                 assigned_zone=excluded.assigned_zone,
                 status=excluded.status, updated_at=excluded.updated_at
            """,
            (
                r.get("resource_id", ""),
                r.get("type", ""),
                r.get("name", ""),
                r.get("total", 1),
                r.get("available", 1),
                r.get("location_desc", ""),
                r.get("assigned_to", ""),
                r.get("assigned_zone", ""),
                r.get("status", "available"),
                now_iso(),
            ),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"save_resource 失敗: {e}", "error")
    finally:
        conn.close()


def get_all_resources() -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM resources ORDER BY type, resource_id"
        ).fetchall()
        resources = _rows_to_dicts(rows)
        allocation_rows = conn.execute(
            "SELECT resource_id, assigned_zone, assigned_to, quantity, location_desc, updated_at "
            "FROM resource_allocations ORDER BY assigned_zone, resource_id"
        ).fetchall()
        allocations_by_resource = {}
        for row in _rows_to_dicts(allocation_rows):
            allocations_by_resource.setdefault(row.get("resource_id", ""), []).append(row)
        for resource in resources:
            allocations = allocations_by_resource.get(resource.get("resource_id", ""), [])
            resource["allocations"] = allocations
            if not resource.get("assigned_zone") and len(allocations) == 1:
                resource["assigned_zone"] = allocations[0].get("assigned_zone", "")
            if not resource.get("assigned_to") and len(allocations) == 1:
                resource["assigned_to"] = allocations[0].get("assigned_to", "")
        return resources
    except Exception as e:
        log_event("error", "db", f"get_all_resources 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_resource(resource_id: str) -> dict | None:
    conn = _get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM resources WHERE resource_id = ?", (resource_id,)
        ).fetchone()
        return dict(row) if row else None
    except Exception as e:
        log_event("error", "db", f"get_resource 失敗: {e}", "error")
        return None
    finally:
        conn.close()


def update_resource(resource_id: str, updates: dict):
    conn = _get_conn()
    try:
        allowed = {"available", "status", "assigned_to", "assigned_zone", "location_desc", "total", "name"}
        sets = []
        vals = []
        for k, v in updates.items():
            if k in allowed:
                sets.append(f"{k} = ?")
                vals.append(v)
        if not sets:
            return
        sets.append("updated_at = ?")
        vals.append(now_iso())
        vals.append(resource_id)
        conn.execute(
            f"UPDATE resources SET {', '.join(sets)} WHERE resource_id = ?",
            vals,
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"update_resource 失敗: {e}", "error")
    finally:
        conn.close()


def upsert_resource_allocation(resource_id: str, assigned_zone: str, quantity: int,
                               location_desc: str = "", assigned_to: str = ""):
    zone = (assigned_zone or "").strip()
    if not zone or quantity <= 0:
        return
    conn = _get_conn()
    try:
        conn.execute(
            """INSERT INTO resource_allocations
               (resource_id, assigned_zone, assigned_to, quantity, location_desc, updated_at)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(resource_id, assigned_zone) DO UPDATE SET
                 quantity=resource_allocations.quantity + excluded.quantity,
                 assigned_to=excluded.assigned_to,
                 location_desc=excluded.location_desc,
                 updated_at=excluded.updated_at
            """,
            (resource_id, zone, assigned_to or zone, quantity, location_desc, now_iso()),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"upsert_resource_allocation 失敗: {e}", "error")
    finally:
        conn.close()


def return_resource_allocation(resource_id: str, assigned_zone: str = "", quantity: int = 1) -> int:
    conn = _get_conn()
    try:
        remaining = max(1, quantity)
        params = [resource_id]
        where = "resource_id = ?"
        if assigned_zone:
            where += " AND assigned_zone = ?"
            params.append(assigned_zone)
        rows = conn.execute(
            f"SELECT id, quantity FROM resource_allocations WHERE {where} ORDER BY updated_at DESC",
            params,
        ).fetchall()
        returned = 0
        for row in rows:
            if remaining <= 0:
                break
            take = min(int(row["quantity"] or 0), remaining)
            if take <= 0:
                continue
            new_quantity = int(row["quantity"]) - take
            if new_quantity <= 0:
                conn.execute("DELETE FROM resource_allocations WHERE id = ?", (row["id"],))
            else:
                conn.execute(
                    "UPDATE resource_allocations SET quantity = ?, updated_at = ? WHERE id = ?",
                    (new_quantity, now_iso(), row["id"]),
                )
            returned += take
            remaining -= take
        conn.commit()
        return returned
    except Exception as e:
        log_event("error", "db", f"return_resource_allocation 失敗: {e}", "error")
        return 0
    finally:
        conn.close()


def get_resource_allocations(resource_id: str) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT resource_id, assigned_zone, assigned_to, quantity, location_desc, updated_at "
            "FROM resource_allocations WHERE resource_id = ? ORDER BY updated_at DESC",
            (resource_id,),
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_resource_allocations 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_resource_summary() -> dict:
    """回傳資源摘要用於 qwen prompt 注入"""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT type, SUM(total) as total, SUM(available) as available "
            "FROM resources GROUP BY type"
        ).fetchall()
        summary = {}
        for r in rows:
            summary[r["type"]] = {
                "total": r["total"] or 0,
                "available": r["available"] or 0,
            }
        return summary
    except Exception as e:
        log_event("error", "db", f"get_resource_summary 失敗: {e}", "error")
        return {}
    finally:
        conn.close()


def get_patient_stats() -> dict:
    """回傳傷患統計（按優先級分類）"""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT priority, COUNT(*) as count FROM patients GROUP BY priority"
        ).fetchall()
        stats = {"total": 0, "red": 0, "yellow": 0, "green": 0, "black": 0}
        priority_map = {"紅色": "red", "黃色": "yellow", "綠色": "green", "黑色": "black"}
        for r in rows:
            key = priority_map.get(r["priority"], "")
            if key:
                stats[key] = r["count"]
            stats["total"] += r["count"]
        return stats
    except Exception as e:
        log_event("error", "db", f"get_patient_stats 失敗: {e}", "error")
        return {"total": 0, "red": 0, "yellow": 0, "green": 0, "black": 0}
    finally:
        conn.close()


# ============================================================
# 查詢函式
# ============================================================

def _rows_to_dicts(rows) -> list:
    return [dict(r) for r in rows]


def get_recent_decisions(n: int = 5) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM decisions ORDER BY id DESC LIMIT ?", (n,)
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_recent_decisions 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_all_patients() -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM patients ORDER BY id"
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_all_patients 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_active_patients() -> list:
    """取得所有 status='active' 的傷患（用於動態重算）"""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM patients WHERE status = 'active' ORDER BY total_score DESC"
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_active_patients 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def update_patient_score(patient_id: str, priority: str, reason: str,
                         start_bonus: float, total_score: float,
                         dimension_data: str):
    """更新單一傷患的評分結果"""
    conn = _get_conn()
    try:
        conn.execute(
            """UPDATE patients SET
                 priority=?, reason=?, start_bonus=?,
                 total_score=?, dimension_data=?, updated_at=?
               WHERE patient_id=?""",
            (priority, reason, start_bonus, total_score,
             dimension_data, now_iso(), patient_id),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"update_patient_score 失敗: {e}", "error")
    finally:
        conn.close()


def deactivate_patient(patient_id: str, new_status: str = "rescued"):
    """將傷患從活動佇列移除（rescued / deceased_confirmed）"""
    conn = _get_conn()
    try:
        conn.execute(
            "UPDATE patients SET status=?, updated_at=? WHERE patient_id=?",
            (new_status, now_iso(), patient_id),
        )
        conn.commit()
    except Exception as e:
        log_event("error", "db", f"deactivate_patient 失敗: {e}", "error")
    finally:
        conn.close()


def get_locations_since(timestamp: str) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM locations WHERE timestamp >= ? ORDER BY timestamp",
            (timestamp,),
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_locations_since 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_reports(limit: int = 20) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM reports ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_reports 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_weather_history(hours: int = 24) -> list:
    since = (datetime.now(TZ_TW) - timedelta(hours=hours)).isoformat()
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM weather_log WHERE timestamp >= ? ORDER BY timestamp",
            (since,),
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_weather_history 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_transcriptions(limit: int = 50) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM transcriptions ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_transcriptions 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_latest_nodes() -> list:
    """取得每個節點的最新狀態（用於系統總覽 / LLM prompt 注入）"""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT n.* FROM node_status_log n "
            "INNER JOIN (SELECT node_id, MAX(id) AS max_id FROM node_status_log GROUP BY node_id) g "
            "ON n.id = g.max_id "
            "ORDER BY n.battery ASC"
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_latest_nodes 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_node_history(node_id: str, hours: int = 1) -> list:
    since = (datetime.now(TZ_TW) - timedelta(hours=hours)).isoformat()
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM node_status_log WHERE node_id = ? AND timestamp >= ? ORDER BY timestamp",
            (node_id, since),
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_node_history 失敗: {e}", "error")
        return []
    finally:
        conn.close()


def get_events_since(timestamp: str) -> list:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT * FROM system_events WHERE timestamp >= ? ORDER BY timestamp",
            (timestamp,),
        ).fetchall()
        return _rows_to_dicts(rows)
    except Exception as e:
        log_event("error", "db", f"get_events_since 失敗: {e}", "error")
        return []
    finally:
        conn.close()


# ============================================================
# 測試
# ============================================================

if __name__ == "__main__":
    print("=" * 60)
    print("LinkGuard DB 初始化測試")
    print("=" * 60)

    init_db()

    # 確認 WAL 模式
    conn = _get_conn()
    mode = conn.execute("PRAGMA journal_mode").fetchone()[0]
    print(f"[TEST] journal_mode = {mode}")
    conn.close()
    assert mode == "wal", f"預期 WAL 模式，實際: {mode}"

    # 測試寫入
    print("\n--- 寫入測試 ---")

    log_event("start", "test", "測試系統啟動", "info")
    print("[TEST] log_event OK")

    save_decision(
        voice_text="現場有三名傷患需要支援",
        patients_summary="[傷員1] 紅色 | [傷員2] 綠色 | [傷員3] 黑色",
        weather_summary="氣溫:28°C | 濕度:75% | 風速:3.2m/s | 雨量:0mm",
        decision_text="【優先處置】立即對傷員1進行急救\n【資源調配】調派EMT前往",
        trigger_type="voice",
    )
    print("[TEST] save_decision OK")

    save_patient({
        "patient_id": "P-001",
        "device_id": "RT-001-EMT",
        "breathing_rate": 35,
        "capillary_refill": 3.0,
        "can_follow_commands": False,
        "location_desc": "A區入口",
        "location_lat": 25.033,
        "location_lon": 121.565,
        "priority": "紅色",
        "reason": "呼吸>30次/分",
        "notes": "",
    })
    print("[TEST] save_patient (insert) OK")

    # 測試 upsert — 更新同一 patient_id
    save_patient({
        "patient_id": "P-001",
        "device_id": "RT-001-EMT",
        "breathing_rate": 28,
        "capillary_refill": 1.8,
        "can_follow_commands": True,
        "location_desc": "A區入口（穩定中）",
        "location_lat": 25.033,
        "location_lon": 121.565,
        "priority": "綠色",
        "reason": "全部正常",
        "notes": "狀況改善",
    })
    print("[TEST] save_patient (upsert) OK")

    save_patient({
        "patient_id": "P-002",
        "breathing_rate": -1,
        "capillary_refill": -1,
        "can_follow_commands": False,
        "location_desc": "B區",
        "priority": "黑色",
        "reason": "無呼吸",
    })
    print("[TEST] save_patient (P-002) OK")

    save_location("RT-001-EMT", "張隊長", "rescue", 25.033, 121.565, 5.0)
    print("[TEST] save_location OK")

    save_report({
        "report_id": "RPT-20260406-001",
        "sender_id": "RT-001-EMT",
        "sender_name": "張隊長",
        "audio_path": "./reports/audio/RPT-20260406-001.m4a",
        "transcription": "現場有三名傷患，一名已無呼吸",
        "location_lat": 25.033,
        "location_lon": 121.565,
        "location_desc": "A區入口",
        "patients_snapshot": '[{"id":"P-001","priority":"紅色"}]',
        "weather_snapshot": '{"temperature":28}',
    })
    print("[TEST] save_report OK")

    save_weather({
        "station_id": "C0A980",
        "temperature": 28.5,
        "humidity": 75.0,
        "wind_speed": 3.2,
        "rainfall": 0.0,
        "obs_time": "2026-04-06T10:00:00+08:00",
    })
    print("[TEST] save_weather OK")

    save_transcription("RT-001-EMT", "現場有三名傷患", "broadcast", 4.5)
    save_transcription("RT-001-EMT", "會報內容：已完成初步檢傷",
                       "report", 12.3, "RPT-20260406-001")
    print("[TEST] save_transcription OK")

    save_node_status({
        "node_id": "HQ-001",
        "rssi": -45,
        "snr": 8.5,
        "battery": 85.0,
        "location": {"lat": 25.034, "lon": 121.566},
        "pdr": 98.5,
        "online": True,
    })
    print("[TEST] save_node_status OK")

    # 測試查詢
    print("\n--- 查詢測試 ---")

    decisions = get_recent_decisions(5)
    print(f"[TEST] decisions: {len(decisions)} 筆")
    for d in decisions:
        print(f"  [{d['timestamp']}] {d['trigger_type']}: {d['decision_text'][:50]}...")

    patients = get_all_patients()
    print(f"[TEST] patients: {len(patients)} 筆")
    for p in patients:
        print(f"  [{p['patient_id']}] {p['priority']} - {p['location_desc']}")
    # 確認 upsert 生效：P-001 應只有 1 筆
    p001_count = sum(1 for p in patients if p["patient_id"] == "P-001")
    assert p001_count == 1, f"P-001 應只有 1 筆 (upsert)，實際: {p001_count}"
    p001 = next(p for p in patients if p["patient_id"] == "P-001")
    assert p001["priority"] == "綠色", f"P-001 應已更新為綠色，實際: {p001['priority']}"
    print("[TEST] upsert 驗證通過 ✓")

    from datetime import datetime as dt
    one_hour_ago = (datetime.now(TZ_TW) - timedelta(hours=1)).isoformat()

    locations = get_locations_since(one_hour_ago)
    print(f"[TEST] locations (1h): {len(locations)} 筆")

    reports = get_reports(20)
    print(f"[TEST] reports: {len(reports)} 筆")

    weather = get_weather_history(24)
    print(f"[TEST] weather (24h): {len(weather)} 筆")

    transcriptions = get_transcriptions(50)
    print(f"[TEST] transcriptions: {len(transcriptions)} 筆")

    nodes = get_node_history("HQ-001", 1)
    print(f"[TEST] node_history (HQ-001, 1h): {len(nodes)} 筆")

    events = get_events_since(one_hour_ago)
    print(f"[TEST] events (1h): {len(events)} 筆")

    print("\n" + "=" * 60)
    print("所有測試通過 ✓")
    print(f"資料庫位置: {os.path.abspath(DB_PATH)}")
    print("=" * 60)
