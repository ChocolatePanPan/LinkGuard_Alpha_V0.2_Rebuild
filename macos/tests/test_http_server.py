"""
Tests for http_server.py – FastAPI report server.

External dependencies (Whisper, TCP server) are mocked.  A temporary
directory and in-memory SQLite path are patched in for each test so the
real filesystem is never touched.
"""
import sys
import os
import json
import sqlite3
import tempfile
import re
from pathlib import Path
from unittest.mock import patch, AsyncMock, MagicMock
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import linkguard_db
import http_server
from starlette.testclient import TestClient


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def tmp_dirs(tmp_path):
    """Patch linkguard_db paths and http_server dirs to use isolated temp directories."""
    db_dir = str(tmp_path / "data")
    db_path = os.path.join(db_dir, "linkguard.db")
    audio = tmp_path / "audio"
    pending = tmp_path / "pending"
    audio.mkdir()
    pending.mkdir()
    with (
        patch.object(linkguard_db, "DB_DIR", db_dir),
        patch.object(linkguard_db, "DB_PATH", db_path),
        patch.object(http_server, "AUDIO_DIR", audio),
        patch.object(http_server, "PENDING_DIR", pending),
    ):
        yield {"db": db_path, "audio": audio, "pending": pending}


@pytest.fixture()
def client(tmp_dirs):
    """Return a TestClient with DB and directories initialised."""
    http_server.init_db()
    return TestClient(http_server.app, raise_server_exceptions=True)


# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

class TestNowIso:
    def test_returns_string(self):
        ts = http_server.now_iso()
        assert isinstance(ts, str)
        assert "T" in ts  # ISO 8601 format

    def test_contains_timezone_offset(self):
        ts = http_server.now_iso()
        assert "+" in ts or "-" in ts or "Z" in ts


class TestGetLocalIp:
    def test_returns_string_ip(self):
        from utils import get_local_ip
        ip = get_local_ip()
        assert isinstance(ip, str)
        # Should look like an IPv4 address
        parts = ip.split(".")
        assert len(parts) == 4

    @patch("utils.socket.getaddrinfo", side_effect=OSError("no addr"))
    @patch("utils.socket.socket")
    @patch.dict(os.environ, {}, clear=True)
    def test_fallback_on_os_error(self, mock_socket_cls, _mock_getaddrinfo):
        mock_sock = MagicMock()
        mock_sock.connect.side_effect = OSError("unreachable")
        mock_sock.getsockname.return_value = ("127.0.0.1", 0)
        mock_socket_cls.return_value = mock_sock
        from utils import get_local_ip
        ip = get_local_ip()
        # When all methods fail, fallback is 127.0.0.1
        assert ip == "127.0.0.1"


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

class TestInitDb:
    def test_creates_reports_table(self, tmp_dirs):
        http_server.init_db()
        conn = sqlite3.connect(tmp_dirs["db"])
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        conn.close()
        table_names = [t[0] for t in tables]
        assert "reports" in table_names
        assert "patients" in table_names

    def test_idempotent(self, tmp_dirs):
        """Calling init_db twice should not raise."""
        http_server.init_db()
        http_server.init_db()


class TestNextReportId:
    def test_first_id_is_001(self, tmp_dirs):
        http_server.init_db()
        rid = http_server.next_report_id()
        # Format: RPT-YYYYMMDD-NNN-xxxx
        parts = rid.split("-")
        assert parts[0] == "RPT"
        assert parts[2] == "001"

    def test_sequential_ids(self, tmp_dirs):
        http_server.init_db()
        rid1 = http_server.next_report_id()
        # Insert the first id so the next call increments
        http_server.save_report(rid1, "d1", "Alice", "/audio/x.m4a", "", 0, 0, "", "[]", "{}")
        rid2 = http_server.next_report_id()
        # Extract the sequence number (3rd component after RPT-YYYYMMDD-NNN-xxxx)
        num1 = int(rid1.split("-")[2])
        num2 = int(rid2.split("-")[2])
        assert num2 == num1 + 1

    def test_format_matches_pattern(self, tmp_dirs):
        http_server.init_db()
        rid = http_server.next_report_id()
        assert re.match(r"^RPT-\d{8}-\d{3}-[0-9a-f]{4}$", rid)


class TestSaveReport:
    def test_saves_and_retrieves(self, tmp_dirs):
        http_server.init_db()
        http_server.save_report(
            "RPT-20240101-001", "dev1", "Bob", "/audio/x.m4a",
            "transcript", 25.0, 121.0, "台北市",
            "[]", "{}",
        )
        conn = sqlite3.connect(tmp_dirs["db"])
        conn.row_factory = sqlite3.Row
        row = conn.execute(
            "SELECT * FROM reports WHERE report_id='RPT-20240101-001'"
        ).fetchone()
        conn.close()
        assert row is not None
        assert row["sender_name"] == "Bob"
        assert row["transcription"] == "transcript"
        assert row["location_lat"] == 25.0


# ---------------------------------------------------------------------------
# GET /reports
# ---------------------------------------------------------------------------

class TestListReports:
    def test_empty_initially(self, client):
        resp = client.get("/reports")
        assert resp.status_code == 200
        assert resp.json()["reports"] == []

    def test_returns_saved_reports(self, client, tmp_dirs):
        http_server.save_report(
            "RPT-20240101-001", "d1", "Alice", "/audio/x.m4a",
            "hello", 25.0, 121.0, "Loc", "[]", "{}",
        )
        resp = client.get("/reports")
        assert resp.status_code == 200
        reports = resp.json()["reports"]
        assert len(reports) == 1
        assert reports[0]["report_id"] == "RPT-20240101-001"


# ---------------------------------------------------------------------------
# GET /audio/{report_id}
# ---------------------------------------------------------------------------

class TestGetAudio:
    def test_invalid_report_id_returns_4xx(self, client):
        # URL normalisation may route this to 404 (no matching route) or 400
        # (regex check in the handler). Both are safe rejections.
        resp = client.get("/audio/../../etc/passwd")
        assert resp.status_code in (400, 404)

    def test_invalid_format_returns_400(self, client):
        resp = client.get("/audio/NOTVALID")
        assert resp.status_code == 400

    def test_valid_format_but_missing_file_returns_404(self, client, tmp_dirs):
        resp = client.get("/audio/RPT-20240101-001")
        assert resp.status_code == 404

    def test_valid_file_served(self, client, tmp_dirs):
        audio_path = tmp_dirs["audio"] / "RPT-20240101-001.m4a"
        audio_path.write_bytes(b"FAKEAUDIO")
        resp = client.get("/audio/RPT-20240101-001")
        assert resp.status_code == 200
        assert resp.content == b"FAKEAUDIO"

    def test_path_traversal_patterns_rejected(self, client):
        for bad in ["RPT-2024010100-001", "RPT-abc-001", "RPT--001", "../secret"]:
            resp = client.get(f"/audio/{bad}")
            assert resp.status_code in (400, 404), f"Expected 400/404 for: {bad}"


# ---------------------------------------------------------------------------
# POST /report
# ---------------------------------------------------------------------------

class TestUploadReport:
    def _fake_audio(self):
        return ("test.m4a", b"FAKEAUDIODATA", "audio/mp4")

    @patch("http_server.send_report_summary_to_tcp")
    @patch("http_server.httpx.AsyncClient")
    def test_successful_upload_returns_ok(
        self, mock_client_cls, mock_tcp, tmp_dirs
    ):
        http_server.init_db()

        # Mock whisper response
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"text": "field report"}
        mock_async_client = AsyncMock()
        mock_async_client.__aenter__ = AsyncMock(return_value=mock_async_client)
        mock_async_client.__aexit__ = AsyncMock(return_value=False)
        mock_async_client.post = AsyncMock(return_value=mock_resp)
        mock_client_cls.return_value = mock_async_client

        with TestClient(http_server.app, raise_server_exceptions=True) as c:
            resp = c.post(
                "/report",
                data={
                    "device_id": "device-001",
                    "sender_name": "Alice",
                    "location_lat": "25.0",
                    "location_lon": "121.0",
                    "location_desc": "台北市",
                    "patients_snapshot": "[]",
                    "weather_snapshot": "{}",
                    "timestamp": "",
                },
                files={"audio": self._fake_audio()},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "ok"
        assert "report_id" in body
        assert body["transcription"] == "field report"

    @patch("http_server.send_report_summary_to_tcp")
    @patch("http_server.httpx.AsyncClient")
    def test_whisper_failure_still_saves_report(
        self, mock_client_cls, mock_tcp, tmp_dirs
    ):
        """If Whisper is unreachable, report is still saved with empty transcription."""
        http_server.init_db()

        mock_async_client = AsyncMock()
        mock_async_client.__aenter__ = AsyncMock(return_value=mock_async_client)
        mock_async_client.__aexit__ = AsyncMock(return_value=False)
        mock_async_client.post = AsyncMock(side_effect=Exception("connection refused"))
        mock_client_cls.return_value = mock_async_client

        with TestClient(http_server.app, raise_server_exceptions=True) as c:
            resp = c.post(
                "/report",
                data={"device_id": "dev2", "patients_snapshot": "[]", "weather_snapshot": "{}"},
                files={"audio": self._fake_audio()},
            )
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"
        # transcription should be empty string
        assert resp.json()["transcription"] == ""

    @patch("http_server.send_report_summary_to_tcp")
    @patch("http_server.httpx.AsyncClient")
    def test_audio_file_is_written_to_disk(
        self, mock_client_cls, mock_tcp, tmp_dirs
    ):
        http_server.init_db()

        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"text": ""}
        mock_async_client = AsyncMock()
        mock_async_client.__aenter__ = AsyncMock(return_value=mock_async_client)
        mock_async_client.__aexit__ = AsyncMock(return_value=False)
        mock_async_client.post = AsyncMock(return_value=mock_resp)
        mock_client_cls.return_value = mock_async_client

        with TestClient(http_server.app, raise_server_exceptions=True) as c:
            resp = c.post(
                "/report",
                data={"device_id": "dev3", "patients_snapshot": "[]", "weather_snapshot": "{}"},
                files={"audio": self._fake_audio()},
            )

        report_id = resp.json()["report_id"]
        audio_file = tmp_dirs["audio"] / f"{report_id}.m4a"
        assert audio_file.exists()
        assert audio_file.read_bytes() == b"FAKEAUDIODATA"


# ---------------------------------------------------------------------------
# _save_pending
# ---------------------------------------------------------------------------

class TestSavePending:
    def test_creates_pending_directory_and_files(self, tmp_dirs):
        http_server._save_pending(
            "RPT-20240101-001", b"AUDIO",
            "dev1", "Alice",
            25.0, 121.0, "Loc",
            "[]", "{}", "2024-01-01T00:00:00",
        )
        entry = tmp_dirs["pending"] / "RPT-20240101-001"
        assert entry.is_dir()
        assert (entry / "audio.m4a").exists()
        assert (entry / "meta.json").exists()

    def test_meta_json_contains_expected_fields(self, tmp_dirs):
        http_server._save_pending(
            "RPT-20240101-002", b"BYTES",
            "devX", "Bob",
            24.0, 120.0, "Kaohsiung",
            "[{\"id\":1}]", "{\"temp\":30}", "ts",
        )
        meta_path = tmp_dirs["pending"] / "RPT-20240101-002" / "meta.json"
        meta = json.loads(meta_path.read_text())
        assert meta["report_id"] == "RPT-20240101-002"
        assert meta["device_id"] == "devX"
        assert meta["retry_count"] == 0

    def test_audio_bytes_are_written(self, tmp_dirs):
        http_server._save_pending(
            "RPT-20240101-003", b"RAWBYTES",
            "d", "N", 0, 0, "", "[]", "{}", "",
        )
        audio = tmp_dirs["pending"] / "RPT-20240101-003" / "audio.m4a"
        assert audio.read_bytes() == b"RAWBYTES"
