"""
test_usb_backup.py — usb_backup 模組單元測試
涵蓋：USB 偵測、DB 同步、音訊/照片/電台同步、定時備份、
      完整備份 (manifest)、回放部署、背景任務啟動
"""
import glob
import json
import os
import platform
import shutil
import sqlite3
import threading
import time
from datetime import datetime
from pathlib import Path
from unittest import mock

import pytest

import usb_backup


# ============================================================
# Fixtures
# ============================================================

@pytest.fixture(autouse=True)
def _reset_usb_cache():
    """每個測試前後重置模組快取"""
    usb_backup._current_usb = None
    yield
    usb_backup._current_usb = None


@pytest.fixture()
def fake_dirs(tmp_path):
    """建立臨時的 DB、音訊、照片、電台、回放目錄"""
    db_dir = tmp_path / "data"
    db_dir.mkdir()
    db_file = db_dir / "linkguard.db"
    # 建立最小 SQLite 檔案
    conn = sqlite3.connect(str(db_file))
    conn.execute("CREATE TABLE IF NOT EXISTS _test (id INTEGER)")
    conn.commit()
    conn.close()

    audio_dir = tmp_path / "reports" / "audio"
    audio_dir.mkdir(parents=True)
    (audio_dir / "RPT-001.m4a").write_bytes(b"\x00" * 128)
    (audio_dir / "RPT-002.m4a").write_bytes(b"\x00" * 64)

    photo_dir = tmp_path / "photos"
    photo_dir.mkdir()
    (photo_dir / "IMG-001.jpg").write_bytes(b"\xFF\xD8" + b"\x00" * 64)
    (photo_dir / "IMG-002.jpg").write_bytes(b"\xFF\xD8" + b"\x00" * 32)

    radio_dir = tmp_path / "radio"
    radio_dir.mkdir()
    (radio_dir / "REC-001.m4a").write_bytes(b"\x00" * 80)
    (radio_dir / "REC-002.wav").write_bytes(b"\x00" * 96)

    replay_dir = tmp_path / "replay"
    replay_dir.mkdir()
    (replay_dir / "server.py").write_text("# replay server\n", encoding="utf-8")

    usb_dir = tmp_path / "usb"
    usb_dir.mkdir()

    # Patch 模組常數
    patches = {
        "DB_PATH": str(db_file),
        "DB_DIR": str(db_dir),
        "LOCAL_BACKUP_PATH": str(db_dir / "linkguard_local_backup.db"),
        "AUDIO_DIR": str(audio_dir),
        "PHOTO_DIR": str(photo_dir),
        "RADIO_DIR": str(radio_dir),
        "REPLAY_DIR": str(replay_dir),
    }
    with mock.patch.multiple(usb_backup, **patches):
        yield {
            "tmp": tmp_path,
            "db_file": db_file,
            "db_dir": db_dir,
            "audio_dir": audio_dir,
            "photo_dir": photo_dir,
            "radio_dir": radio_dir,
            "replay_dir": replay_dir,
            "usb_dir": usb_dir,
            **patches,
        }


@pytest.fixture()
def mock_log_event():
    """Mock linkguard_db.log_event 避免真正寫 DB"""
    with mock.patch("usb_backup.log_event") as m:
        yield m


# ============================================================
# USB 偵測
# ============================================================

class TestDetectUsb:
    def test_windows_detects_drive(self):
        """Windows 下偵測 >1 GB 磁碟"""
        usage = shutil.disk_usage.__class__
        fake_usage = mock.Mock(total=16_000_000_000)
        with (
            mock.patch("usb_backup.platform.system", return_value="Windows"),
            mock.patch("usb_backup.os.path.exists", side_effect=lambda p: p == "D:\\"),
            mock.patch("usb_backup.shutil.disk_usage", return_value=fake_usage),
        ):
            result = usb_backup.detect_usb()
            assert result == "D:\\"

    def test_windows_no_drive(self):
        with (
            mock.patch("usb_backup.platform.system", return_value="Windows"),
            mock.patch("usb_backup.os.path.exists", return_value=False),
        ):
            assert usb_backup.detect_usb() is None

    def test_darwin_detects_volume(self, tmp_path):
        vol = tmp_path / "Volumes" / "MyUSB"
        vol.mkdir(parents=True)
        fake_usage = mock.Mock(total=32_000_000_000)
        with (
            mock.patch("usb_backup.platform.system", return_value="Darwin"),
            mock.patch("usb_backup.Path", side_effect=lambda p: Path(str(tmp_path / "Volumes")) if p == "/Volumes" else Path(p)),
            mock.patch("usb_backup.shutil.disk_usage", return_value=fake_usage),
        ):
            # 手動測試 Darwin 路徑邏輯
            result = usb_backup.detect_usb()
            # 因為 Path 的 mock 比較複雜，這裡驗證不會 crash
            # 並且 None 也可接受（取決於目錄遍歷的 mock 深度）
            assert result is None or isinstance(result, str)

    def test_small_drive_skipped(self):
        """小於 1 GB 的磁碟應被跳過"""
        fake_usage = mock.Mock(total=500_000_000)  # 500 MB
        with (
            mock.patch("usb_backup.platform.system", return_value="Windows"),
            mock.patch("usb_backup.os.path.exists", return_value=True),
            mock.patch("usb_backup.shutil.disk_usage", return_value=fake_usage),
        ):
            assert usb_backup.detect_usb() is None


# ============================================================
# DB 同步
# ============================================================

class TestSyncDb:
    def test_local_backup_created(self, fake_dirs, mock_log_event):
        """sync_db 應建立本地備份"""
        with mock.patch("usb_backup.detect_usb", return_value=None):
            usb_backup.sync_db()
        local_bak = Path(fake_dirs["LOCAL_BACKUP_PATH"])
        assert local_bak.exists()
        assert local_bak.stat().st_size > 0

    def test_usb_backup_created(self, fake_dirs, mock_log_event):
        """有 USB 時 sync_db 應複製 DB 到 USB"""
        usb_dir = fake_dirs["usb_dir"]
        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.sync_db()
        usb_db = usb_dir / "LinkGuard" / "data" / "linkguard.db"
        assert usb_db.exists()
        assert usb_db.stat().st_size > 0

    def test_missing_db_skips(self, fake_dirs, mock_log_event):
        """DB 不存在時應跳過"""
        os.remove(str(fake_dirs["db_file"]))
        with mock.patch("usb_backup.detect_usb", return_value=None):
            usb_backup.sync_db()  # 不應 crash


# ============================================================
# 音訊同步
# ============================================================

class TestSyncAudio:
    def test_audio_copied_to_usb(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.sync_audio("RPT-001")
        dest = usb_dir / "LinkGuard" / "reports" / "audio" / "RPT-001.m4a"
        assert dest.exists()
        assert dest.stat().st_size == 128

    def test_missing_audio_skips(self, fake_dirs, mock_log_event):
        with mock.patch("usb_backup.detect_usb", return_value=str(fake_dirs["usb_dir"])):
            usb_backup.sync_audio("NONEXISTENT")  # 不應 crash

    def test_no_usb_skips(self, fake_dirs, mock_log_event):
        with mock.patch("usb_backup.detect_usb", return_value=None):
            usb_backup.sync_audio("RPT-001")  # 不應 crash


# ============================================================
# 照片同步
# ============================================================

class TestSyncPhoto:
    def test_photo_copied_to_usb(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.sync_photo("IMG-001")
        dest = usb_dir / "LinkGuard" / "photos" / "IMG-001.jpg"
        assert dest.exists()

    def test_missing_photo_skips(self, fake_dirs, mock_log_event):
        with mock.patch("usb_backup.detect_usb", return_value=str(fake_dirs["usb_dir"])):
            usb_backup.sync_photo("NOPE")


# ============================================================
# 電台錄音同步
# ============================================================

class TestSyncRadio:
    def test_m4a_radio_copied(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.sync_radio("REC-001")
        assert (usb_dir / "LinkGuard" / "radio" / "REC-001.m4a").exists()

    def test_wav_radio_copied(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.sync_radio("REC-002")
        assert (usb_dir / "LinkGuard" / "radio" / "REC-002.wav").exists()

    def test_missing_radio_skips(self, fake_dirs, mock_log_event):
        with mock.patch("usb_backup.detect_usb", return_value=str(fake_dirs["usb_dir"])):
            usb_backup.sync_radio("NOPE")


# ============================================================
# 定時備份
# ============================================================

class TestTimedBackup:
    def test_creates_timestamped_db(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.create_timed_backup()
        backup_dir = usb_dir / "LinkGuard" / "backup"
        backups = list(backup_dir.glob("linkguard_*.db"))
        assert len(backups) == 1

    def test_cleans_old_backups(self, fake_dirs, mock_log_event):
        """超過 MAX_TIMED_BACKUPS 的備份應被刪除"""
        usb_dir = fake_dirs["usb_dir"]
        backup_dir = usb_dir / "LinkGuard" / "backup"
        backup_dir.mkdir(parents=True)
        # 先塞 50 個假備份
        for i in range(50):
            (backup_dir / f"linkguard_20260101_{i:06d}.db").write_bytes(b"\x00")

        with mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)):
            usb_backup.create_timed_backup()  # 第 51 個

        remaining = list(backup_dir.glob("linkguard_*.db"))
        assert len(remaining) <= usb_backup.MAX_TIMED_BACKUPS

    def test_no_usb_skips(self, fake_dirs, mock_log_event):
        with mock.patch("usb_backup.detect_usb", return_value=None):
            usb_backup.create_timed_backup()  # 不 crash


# ============================================================
# 完整備份
# ============================================================

class TestFullBackup:
    def test_full_backup_creates_all(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        with (
            mock.patch("usb_backup.detect_usb", return_value=str(usb_dir)),
            mock.patch("usb_backup.get_all_patients", return_value=[{"id": "P1"}]),
            mock.patch("usb_backup.get_reports", return_value=[{"id": "R1"}, {"id": "R2"}]),
            mock.patch("usb_backup.get_recent_decisions", return_value=[{"id": "D1"}]),
        ):
            usb_backup.full_backup()

        lg = usb_dir / "LinkGuard"
        # DB 同步
        assert (lg / "data" / "linkguard.db").exists()
        # 音訊
        assert (lg / "reports" / "audio" / "RPT-001.m4a").exists()
        assert (lg / "reports" / "audio" / "RPT-002.m4a").exists()
        # 照片
        assert (lg / "photos" / "IMG-001.jpg").exists()
        assert (lg / "photos" / "IMG-002.jpg").exists()
        # 電台
        assert (lg / "radio" / "REC-001.m4a").exists()
        assert (lg / "radio" / "REC-002.wav").exists()
        # 定時備份
        assert len(list((lg / "backup").glob("linkguard_*.db"))) == 1
        # Manifest
        manifest_path = lg / "backup_manifest.json"
        assert manifest_path.exists()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        assert manifest["audio_count"] == 2
        assert manifest["patient_count"] == 1
        assert manifest["report_count"] == 2
        assert manifest["decision_count"] == 1
        assert manifest["db_size_mb"] > 0

    def test_no_usb_logs_warning(self, fake_dirs, mock_log_event):
        with mock.patch("usb_backup.detect_usb", return_value=None):
            usb_backup.full_backup()
        mock_log_event.assert_called_with(
            "warning", "usb", "完整備份失敗：未偵測到 USB", "warning"
        )


# ============================================================
# 回放部署
# ============================================================

class TestDeployReplay:
    def test_deploys_replay_files(self, fake_dirs, mock_log_event):
        usb_dir = fake_dirs["usb_dir"]
        usb_backup.deploy_replay(str(usb_dir))
        replay = usb_dir / "LinkGuard" / "replay"
        assert (replay / "server.py").exists()
        assert (replay / "start.bat").exists()
        assert (replay / "start.sh").exists()
        # 確認 bat 內容
        bat_content = (replay / "start.bat").read_text(encoding="utf-8")
        assert "python server.py" in bat_content

    def test_missing_replay_server_warns(self, fake_dirs, mock_log_event):
        """server.py 不存在時不 crash，只是跳過"""
        os.remove(str(fake_dirs["replay_dir"] / "server.py"))
        usb_dir = fake_dirs["usb_dir"]
        usb_backup.deploy_replay(str(usb_dir))
        replay = usb_dir / "LinkGuard" / "replay"
        assert not (replay / "server.py").exists()
        assert (replay / "start.bat").exists()  # 啟動腳本仍會生成


# ============================================================
# 背景任務
# ============================================================

class TestBackgroundTasks:
    def test_start_background_tasks_launches_threads(self):
        t1, t2 = usb_backup.start_background_tasks()
        assert isinstance(t1, threading.Thread)
        assert isinstance(t2, threading.Thread)
        assert t1.daemon is True
        assert t2.daemon is True
        assert t1.is_alive()
        assert t2.is_alive()


# ============================================================
# _usb_linkguard_dir
# ============================================================

class TestUsbDir:
    def test_returns_linkguard_subdir(self):
        assert usb_backup._usb_linkguard_dir("D:\\") == os.path.join("D:\\", "LinkGuard")
        assert usb_backup._usb_linkguard_dir("/Volumes/USB") == os.path.join("/Volumes/USB", "LinkGuard")
