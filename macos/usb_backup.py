"""
usb_backup.py — LinkGuard USB 雙備份管理模組
管理 USB 自動偵測、資料庫同步、音訊備份、定時備份
"""
from __future__ import annotations

import glob
import json
import os
import platform
import shutil
import sqlite3
import threading
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

from linkguard_db import (
    DB_PATH, DB_DIR, TZ_TW, now_iso,
    log_event, get_all_patients, get_reports, get_recent_decisions,
)

# === 設定 ===
AUDIO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reports", "audio")
PHOTO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "photos")
RADIO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "radio")
LOCAL_BACKUP_PATH = os.path.join(DB_DIR, "linkguard_local_backup.db")
REPLAY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "replay")
MAX_TIMED_BACKUPS = 48

SYNC_DB_INTERVAL = 15 * 60       # 15 分鐘
TIMED_BACKUP_INTERVAL = 60 * 60  # 60 分鐘

# 備份執行中的 USB 路徑快取
_current_usb: str | None = None


# ============================================================
# USB 偵測
# ============================================================

def detect_usb() -> str | None:
    """掃描並回傳可用 USB 路徑，未插入回傳 None"""
    system = platform.system()

    if system == "Windows":
        for letter in "DEFGH":
            drive = f"{letter}:\\"
            if os.path.exists(drive):
                try:
                    usage = shutil.disk_usage(drive)
                    if usage.total > 1_000_000_000:  # > 1 GB
                        print(f"[USB] 偵測到 USB: {drive} ({usage.total / 1e9:.1f} GB)")
                        return drive
                except OSError:
                    continue

    elif system == "Darwin":  # macOS
        volumes = Path("/Volumes")
        if volumes.exists():
            for vol in volumes.iterdir():
                if vol.name == "Macintosh HD":
                    continue
                try:
                    usage = shutil.disk_usage(str(vol))
                    if usage.total > 1_000_000_000:
                        print(f"[USB] 偵測到 USB: {vol} ({usage.total / 1e9:.1f} GB)")
                        return str(vol)
                except OSError:
                    continue

    else:  # Linux
        for base in ["/media", f"/media/{os.getenv('USER', '')}",
                     "/mnt", "/run/media"]:
            base_path = Path(base)
            if not base_path.exists():
                continue
            for vol in base_path.iterdir():
                try:
                    usage = shutil.disk_usage(str(vol))
                    if usage.total > 1_000_000_000:
                        print(f"[USB] 偵測到 USB: {vol} ({usage.total / 1e9:.1f} GB)")
                        return str(vol)
                except OSError:
                    continue

    print("[USB] 未偵測到 USB 隨身碟")
    return None


def _usb_linkguard_dir(usb_path: str) -> str:
    return os.path.join(usb_path, "LinkGuard")


# ============================================================
# 同步函式
# ============================================================

def sync_db():
    """複製 linkguard.db 到 USB 及本地備份"""
    global _current_usb

    if not os.path.exists(DB_PATH):
        print("[USB] 資料庫不存在，跳過同步")
        return

    # 本地備份
    try:
        shutil.copy2(DB_PATH, LOCAL_BACKUP_PATH)
        print(f"[USB] 本地備份完成: {LOCAL_BACKUP_PATH}")
    except Exception as e:
        log_event("error", "backup", f"本地備份失敗: {e}", "error")

    # USB 備份
    usb = _current_usb or detect_usb()
    if not usb:
        return

    try:
        usb_data = os.path.join(_usb_linkguard_dir(usb), "data")
        os.makedirs(usb_data, exist_ok=True)
        dest = os.path.join(usb_data, "linkguard.db")
        shutil.copy2(DB_PATH, dest)
        print(f"[USB] DB 同步完成: {dest}")
        log_event("backup", "usb", f"DB 同步至 USB: {dest}", "info")
    except OSError as e:
        log_event("error", "usb", f"USB DB 同步失敗: {e}", "error")


def sync_audio(report_id: str):
    """複製單一音訊檔案到 USB"""
    global _current_usb

    src = os.path.join(AUDIO_DIR, f"{report_id}.m4a")
    if not os.path.exists(src):
        print(f"[USB] 音訊檔案不存在: {src}")
        return

    usb = _current_usb or detect_usb()
    if not usb:
        return

    try:
        usb_audio = os.path.join(_usb_linkguard_dir(usb), "reports", "audio")
        os.makedirs(usb_audio, exist_ok=True)
        dest = os.path.join(usb_audio, f"{report_id}.m4a")
        shutil.copy2(src, dest)
        print(f"[USB] 音訊同步完成: {dest}")
    except OSError as e:
        log_event("error", "usb", f"USB 音訊同步失敗 ({report_id}): {e}", "error")


def sync_photo(photo_id: str):
    """複製單一照片檔案到 USB"""
    global _current_usb

    src = os.path.join(PHOTO_DIR, f"{photo_id}.jpg")
    if not os.path.exists(src):
        print(f"[USB] 照片檔案不存在: {src}")
        return

    usb = _current_usb or detect_usb()
    if not usb:
        return

    try:
        usb_photo = os.path.join(_usb_linkguard_dir(usb), "photos")
        os.makedirs(usb_photo, exist_ok=True)
        dest = os.path.join(usb_photo, f"{photo_id}.jpg")
        shutil.copy2(src, dest)
        print(f"[USB] 照片同步完成: {dest}")
    except OSError as e:
        log_event("error", "usb", f"USB 照片同步失敗 ({photo_id}): {e}", "error")


def sync_radio(radio_id: str):
    """複製單一電台錄音檔案到 USB"""
    global _current_usb

    # 假設副檔名為 m4a 或 wav，這裡以最通用的方式複製
    src = os.path.join(RADIO_DIR, f"{radio_id}.m4a")
    if not os.path.exists(src):
        src = os.path.join(RADIO_DIR, f"{radio_id}.wav")
        if not os.path.exists(src):
            print(f"[USB] 電台錄音檔案不存在: {src}")
            return

    ext = os.path.splitext(src)[1]
    usb = _current_usb or detect_usb()
    if not usb:
        return

    try:
        usb_radio = os.path.join(_usb_linkguard_dir(usb), "radio")
        os.makedirs(usb_radio, exist_ok=True)
        dest = os.path.join(usb_radio, f"{radio_id}{ext}")
        shutil.copy2(src, dest)
        print(f"[USB] 電台錄音同步完成: {dest}")
    except OSError as e:
        log_event("error", "usb", f"USB 電台錄音同步失敗 ({radio_id}): {e}", "error")


def create_timed_backup():
    """建立帶時間戳的 DB 備份，保留最近 48 個"""
    global _current_usb

    if not os.path.exists(DB_PATH):
        return

    usb = _current_usb or detect_usb()
    if not usb:
        # 無 USB 時也做本地備份
        return

    try:
        backup_dir = os.path.join(_usb_linkguard_dir(usb), "backup")
        os.makedirs(backup_dir, exist_ok=True)

        ts = datetime.now(TZ_TW).strftime("%Y%m%d_%H%M%S")
        dest = os.path.join(backup_dir, f"linkguard_{ts}.db")
        shutil.copy2(DB_PATH, dest)
        print(f"[USB] 定時備份完成: {dest}")

        # 清理舊備份
        backups = sorted(glob.glob(os.path.join(backup_dir, "linkguard_*.db")))
        if len(backups) > MAX_TIMED_BACKUPS:
            for old in backups[: len(backups) - MAX_TIMED_BACKUPS]:
                os.remove(old)
                print(f"[USB] 刪除舊備份: {old}")

        log_event("backup", "usb", f"定時備份: {dest}", "info")
    except OSError as e:
        log_event("error", "usb", f"定時備份失敗: {e}", "error")


def full_backup():
    """完整備份：DB + 所有音訊 + 定時備份 + manifest"""
    global _current_usb

    usb = _current_usb or detect_usb()
    if not usb:
        log_event("warning", "usb", "完整備份失敗：未偵測到 USB", "warning")
        return

    _current_usb = usb
    print(f"[USB] 開始完整備份至 {usb}")

    # 1. 同步 DB
    sync_db()

    # 2. 同步所有音訊與多媒體檔案
    audio_count = 0
    if os.path.isdir(AUDIO_DIR):
        for f in os.listdir(AUDIO_DIR):
            if f.endswith(".m4a"):
                report_id = f.replace(".m4a", "")
                sync_audio(report_id)
                audio_count += 1
                
    photo_count = 0
    if os.path.isdir(PHOTO_DIR):
        for f in os.listdir(PHOTO_DIR):
            if f.endswith(".jpg"):
                photo_id = f.replace(".jpg", "")
                sync_photo(photo_id)
                photo_count += 1
                
    radio_count = 0
    if os.path.isdir(RADIO_DIR):
        for f in os.listdir(RADIO_DIR):
            if f.endswith(".m4a") or f.endswith(".wav"):
                radio_id = os.path.splitext(f)[0]
                sync_radio(radio_id)
                radio_count += 1

    # 3. 定時備份
    create_timed_backup()

    # 4. 寫入 manifest
    try:
        patients = get_all_patients()
        reports = get_reports(limit=999999)
        decisions = get_recent_decisions(n=999999)

        db_size = os.path.getsize(DB_PATH) / (1024 * 1024) if os.path.exists(DB_PATH) else 0.0

        manifest = {
            "backup_time": now_iso(),
            "db_size_mb": round(db_size, 2),
            "audio_count": audio_count,
            "patient_count": len(patients),
            "report_count": len(reports),
            "decision_count": len(decisions),
        }

        manifest_path = os.path.join(_usb_linkguard_dir(usb), "backup_manifest.json")
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"[USB] Manifest 已寫入: {manifest_path}")
        print(f"[USB] 完整備份完成 — DB:{manifest['db_size_mb']}MB, "
              f"Audio:{audio_count}, Patients:{len(patients)}, "
              f"Reports:{len(reports)}, Decisions:{len(decisions)}")
        log_event("backup", "usb",
                  f"完整備份完成: {json.dumps(manifest, ensure_ascii=False)}",
                  "info")
    except Exception as e:
        log_event("error", "usb", f"Manifest 寫入失敗: {e}", "error")


# ============================================================
# 回放部署
# ============================================================

def deploy_replay(usb_path: str):
    """部署回放程式到 USB"""
    try:
        usb_replay = os.path.join(_usb_linkguard_dir(usb_path), "replay")
        os.makedirs(usb_replay, exist_ok=True)

        # 複製 server.py
        src_server = os.path.join(REPLAY_DIR, "server.py")
        if os.path.exists(src_server):
            shutil.copy2(src_server, os.path.join(usb_replay, "server.py"))
            print(f"[USB] 已部署 server.py 到 {usb_replay}")
        else:
            print(f"[USB] 警告: {src_server} 不存在，跳過 server.py 部署")

        # 生成 start.bat
        bat_path = os.path.join(usb_replay, "start.bat")
        with open(bat_path, "w", encoding="utf-8") as f:
            f.write("@echo off\npython server.py\npause\n")

        # 生成 start.sh
        sh_path = os.path.join(usb_replay, "start.sh")
        with open(sh_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("#!/bin/bash\npython3 server.py\n")

        print(f"[USB] 已部署啟動腳本到 {usb_replay}")
        log_event("backup", "usb", f"回放程式已部署至 {usb_replay}", "info")
    except Exception as e:
        log_event("error", "usb", f"回放部署失敗: {e}", "error")


# ============================================================
# 背景定時任務
# ============================================================

def _periodic_sync_db():
    """背景執行：每 15 分鐘同步 DB"""
    while True:
        time.sleep(SYNC_DB_INTERVAL)
        try:
            sync_db()
        except Exception as e:
            print(f"[USB] 定時 DB 同步失敗: {e}")


def _periodic_timed_backup():
    """背景執行：每 60 分鐘建立定時備份"""
    while True:
        time.sleep(TIMED_BACKUP_INTERVAL)
        try:
            create_timed_backup()
        except Exception as e:
            print(f"[USB] 定時備份失敗: {e}")


def start_background_tasks():
    """啟動背景同步線程"""
    t1 = threading.Thread(target=_periodic_sync_db, daemon=True,
                          name="usb-sync-db")
    t2 = threading.Thread(target=_periodic_timed_backup, daemon=True,
                          name="usb-timed-backup")
    t1.start()
    t2.start()
    print("[USB] 背景任務已啟動 (sync_db: 15min, timed_backup: 60min)")
    return t1, t2


# ============================================================
# 主程式
# ============================================================

if __name__ == "__main__":
    print("=" * 60)
    print("LinkGuard USB Backup 測試")
    print("=" * 60)

    # 確保 DB 已初始化
    from linkguard_db import init_db
    init_db()

    # 偵測 USB
    usb = detect_usb()

    if usb:
        print(f"\n[TEST] USB 偵測到: {usb}")
        _current_usb = usb

        # 完整備份
        full_backup()

        # 部署回放程式
        deploy_replay(usb)

        # 顯示 USB 目錄結構
        lg_dir = _usb_linkguard_dir(usb)
        print(f"\n[TEST] USB 目錄結構 ({lg_dir}):")
        for root, dirs, files in os.walk(lg_dir):
            level = root.replace(lg_dir, "").count(os.sep)
            indent = "  " * level
            print(f"  {indent}{os.path.basename(root)}/")
            for f in files:
                size = os.path.getsize(os.path.join(root, f))
                print(f"  {indent}  {f} ({size:,} bytes)")
    else:
        print("\n[TEST] 無 USB，執行本地備份")
        sync_db()
        print(f"[TEST] 本地備份: {LOCAL_BACKUP_PATH}")
        if os.path.exists(LOCAL_BACKUP_PATH):
            size = os.path.getsize(LOCAL_BACKUP_PATH)
            print(f"[TEST] 備份大小: {size:,} bytes")

    # 啟動背景任務測試
    print("\n[TEST] 啟動背景任務...")
    start_background_tasks()
    print("[TEST] 背景任務運行中，按 Ctrl+C 結束")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[TEST] 結束")
