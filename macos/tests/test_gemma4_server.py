"""
Tests for gemma4_server.py – SQLite memory helpers and FastAPI endpoints.

The `ollama` module is stubbed out via sys.modules so no real LLM is needed.
"""
import sys
import os
import json
import sqlite3
import tempfile
import pytest
from unittest.mock import patch, MagicMock

# ---------------------------------------------------------------------------
# Stub out ollama before importing gemma4_server
# ---------------------------------------------------------------------------
ollama_stub = MagicMock()
sys.modules.setdefault("ollama", ollama_stub)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import linkguard_db
import gemma4_server as qwen_server
from starlette.testclient import TestClient


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def tmp_db(tmp_path):
    """Patch linkguard_db paths to an isolated temp dir and initialise."""
    db_dir = str(tmp_path / "data")
    db_path = os.path.join(db_dir, "linkguard.db")
    with patch.object(linkguard_db, "DB_DIR", db_dir), \
         patch.object(linkguard_db, "DB_PATH", db_path):
        linkguard_db.init_db()
        yield db_path


@pytest.fixture()
def client(tmp_db):
    """Return a TestClient with an isolated database."""
    return TestClient(qwen_server.app, raise_server_exceptions=True)


@pytest.fixture(autouse=True)
def reset_active_model():
    """Reset the active model and dual config to default before each test."""
    qwen_server._active_model = qwen_server.MODEL_NAME
    original_dual = dict(qwen_server.DUAL_CFG)
    qwen_server.DUAL_CFG["enabled"] = False
    yield
    qwen_server._active_model = qwen_server.MODEL_NAME
    qwen_server.DUAL_CFG.clear()
    qwen_server.DUAL_CFG.update(original_dual)


# ---------------------------------------------------------------------------
# init_db
# ---------------------------------------------------------------------------

class TestInitDb:
    def test_creates_decisions_table(self, tmp_db):
        conn = sqlite3.connect(tmp_db)
        tables = [
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        ]
        conn.close()
        assert "decisions" in tables

    def test_creates_patients_table(self, tmp_db):
        conn = sqlite3.connect(tmp_db)
        tables = [
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        ]
        conn.close()
        assert "patients" in tables

    def test_idempotent(self, tmp_db):
        """Calling init_db a second time must not raise."""
        linkguard_db.init_db()


# ---------------------------------------------------------------------------
# save_decision / get_recent_decisions
# ---------------------------------------------------------------------------

class TestDecisionMemory:
    def test_save_and_retrieve_single_decision(self, tmp_db):
        qwen_server.save_decision("voice1", "patients1", "weather1", "decision1")
        result = qwen_server.get_recent_decisions(5)
        assert "decision1" in result

    def test_no_decisions_returns_placeholder(self, tmp_db):
        result = qwen_server.get_recent_decisions()
        assert "尚無" in result

    def test_multiple_decisions_returned_in_chronological_order(self, tmp_db):
        for i in range(3):
            qwen_server.save_decision(f"v{i}", f"p{i}", f"w{i}", f"decision{i}")
        result = qwen_server.get_recent_decisions(5)
        # All three decisions should appear
        for i in range(3):
            assert f"decision{i}" in result

    def test_limit_parameter_respected(self, tmp_db):
        for i in range(10):
            qwen_server.save_decision("v", "p", "w", f"decision{i:03d}")
        result = qwen_server.get_recent_decisions(3)
        # Only 3 most recent decisions should be present; earlier ones omitted
        lines = [l for l in result.strip().split("\n") if l]
        assert len(lines) == 3
        # The 3 most recent decisions are decision007, decision008, decision009
        assert "decision007" in result
        assert "decision008" in result
        assert "decision009" in result
        assert "decision000" not in result

    def test_long_decision_is_truncated_in_summary(self, tmp_db):
        long_text = "X" * 300
        qwen_server.save_decision("v", "p", "w", long_text)
        result = qwen_server.get_recent_decisions(1)
        # Summary is truncated to 120 chars; verify the output is shorter
        line = result.strip().split("\n")[0]
        # The line should not contain 300 X's
        assert "X" * 200 not in line

    def test_decision_contains_timestamp(self, tmp_db):
        qwen_server.save_decision("v", "p", "w", "d")
        result = qwen_server.get_recent_decisions(1)
        # Timestamp is in ISO format, starts with [
        assert "[" in result


# ---------------------------------------------------------------------------
# GET /history
# ---------------------------------------------------------------------------

class TestGetHistory:
    def test_empty_history_returns_empty_list(self, client, tmp_db):
        resp = client.get("/history")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["history"] == []

    def test_returns_saved_decisions(self, client, tmp_db):
        qwen_server.save_decision("voice text", "patients", "weather", "decision text")
        resp = client.get("/history")
        assert resp.status_code == 200
        data = resp.json()
        items = data["history"]
        assert len(items) == 1
        assert items[0]["voice_text"] == "voice text"
        assert items[0]["decision_text"] == "decision text"

    def test_returns_at_most_10_items(self, client, tmp_db):
        for i in range(15):
            qwen_server.save_decision("v", "p", "w", f"d{i}")
        resp = client.get("/history")
        assert len(resp.json()["history"]) == 10


# ---------------------------------------------------------------------------
# DELETE /history
# ---------------------------------------------------------------------------

class TestClearHistory:
    def test_clears_all_decisions(self, client, tmp_db):
        for i in range(3):
            qwen_server.save_decision("v", "p", "w", f"d{i}")
        client.delete("/history")
        resp = client.get("/history")
        assert resp.json()["history"] == []

    def test_returns_confirmation_message(self, client, tmp_db):
        resp = client.delete("/history")
        assert resp.status_code == 200
        assert "清除" in resp.json()["message"] or "cleared" in resp.json().get("message", "").lower()


# ---------------------------------------------------------------------------
# POST /generate – happy path with mocked ollama
# ---------------------------------------------------------------------------

class TestGenerate:
    @pytest.fixture()
    def mock_ollama(self):
        """Make ollama.Client().chat() return a fake decision."""
        mock_response = MagicMock()
        mock_response.message.content = "【優先處置】移送紅色傷患"
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield mock_client_instance

    def test_generate_returns_decision_and_patients(self, client, tmp_db, mock_ollama):
        payload = {
            "voice_text": "現場有三名傷患",
            "patients": [
                {"id": "P1", "breathing_rate": 18, "capillary_refill": 1.0, "can_follow_commands": True},
                {"id": "P2", "breathing_rate": -1, "capillary_refill": 0, "can_follow_commands": False},
            ],
            "weather": {"temperature": 28.0, "humidity": 75.0, "wind_speed": 2.0, "rainfall": 0.0},
            "resources": "3名救護員",
        }
        resp = client.post("/generate", json=payload)
        assert resp.status_code == 200
        body = resp.json()
        assert "decision" in body
        assert "patients" in body
        assert len(body["patients"]) == 2

    def test_generate_applies_triage_to_patients(self, client, tmp_db, mock_ollama):
        payload = {
            "voice_text": "",
            "patients": [
                {"id": "P1", "breathing_rate": -1},
                {"id": "P2", "breathing_rate": 18, "capillary_refill": 1.0, "can_follow_commands": True},
            ],
            "weather": {},
            "resources": "",
        }
        resp = client.post("/generate", json=payload)
        patients = resp.json()["patients"]
        priorities = {p["id"]: p["priority"] for p in patients}
        assert priorities["P1"] == "黑色"
        assert priorities["P2"] == "綠色"

    def test_generate_saves_decision_to_db(self, client, tmp_db, mock_ollama):
        payload = {
            "voice_text": "test",
            "patients": [],
            "weather": {},
            "resources": "",
        }
        client.post("/generate", json=payload)
        history_resp = client.get("/history")
        assert len(history_resp.json()["history"]) == 1

    def test_generate_empty_weather_uses_placeholder(self, client, tmp_db, mock_ollama):
        """Empty weather dict should not raise; 'no weather' message is used."""
        payload = {
            "voice_text": "",
            "patients": [],
            "weather": {},
            "resources": "",
        }
        resp = client.post("/generate", json=payload)
        assert resp.status_code == 200

    def test_generate_with_reasoning_returns_reasoning_block(self, client, tmp_db, mock_ollama):
        decision_resp = MagicMock()
        decision_resp.message.content = "【優先處置】先救援紅色傷患"
        reasoning_resp = MagicMock()
        reasoning_resp.message.content = (
            '{"reason_summary":["紅色傷患呼吸異常"],'
            '"risk_notes":["現場有二次災害風險"],'
            '"next_actions":["立即派遣兩名救護員"]}'
        )
        mock_ollama.chat.side_effect = [decision_resp, reasoning_resp]

        payload = {
            "voice_text": "現場有高風險傷患",
            "patients": [
                {"id": "P1", "breathing_rate": 35, "capillary_refill": 3.0, "can_follow_commands": False}
            ],
            "weather": {},
            "resources": "2名救護員",
            "show_reasoning": True,
        }
        resp = client.post("/generate", json=payload)
        assert resp.status_code == 200
        body = resp.json()
        assert "reasoning" in body
        assert body["reasoning"]["reason_summary"]
        assert body["reasoning"]["risk_notes"]
        assert body["reasoning"]["next_actions"]


# ---------------------------------------------------------------------------
# /translate endpoint
# ---------------------------------------------------------------------------

class TestTranslate:
    @pytest.fixture()
    def mock_ollama(self):
        """Make ollama.Client().chat() return a fake translation."""
        mock_response = MagicMock()
        mock_response.message.content = "Hello"
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance) as mock_cls:
            mock_cls.return_value = mock_client_instance
            yield mock_cls

    def test_translate_success(self, client, mock_ollama):
        """POST /translate should return translated text."""
        mock_ollama.Client.return_value.chat.return_value = MagicMock(
            message=MagicMock(content="Hello")
        )
        resp = client.post("/translate", json={
            "text": "你好",
            "source_lang": "zh-TW",
            "target_lang": "en",
            "context": "medical",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["original"] == "你好"
        assert data["translated"] == "Hello"
        assert data["target_lang"] == "en"
        assert data["detected_lang"] == "zh-TW"

    def test_translate_auto_detect(self, client, mock_ollama):
        """source_lang=auto should default detected_lang to zh-TW."""
        mock_ollama.Client.return_value.chat.return_value = MagicMock(
            message=MagicMock(content="こんにちは")
        )
        resp = client.post("/translate", json={
            "text": "你好",
            "source_lang": "auto",
            "target_lang": "ja",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["detected_lang"] == "zh-TW"
        assert data["target_lang"] == "ja"

    def test_translate_missing_text(self, client):
        """Missing required field 'text' should 422."""
        resp = client.post("/translate", json={
            "target_lang": "en",
        })
        assert resp.status_code == 422

    def test_translate_defaults(self, client, mock_ollama):
        """Default source_lang=auto, target_lang=en."""
        mock_ollama.Client.return_value.chat.return_value = MagicMock(
            message=MagicMock(content="Help")
        )
        resp = client.post("/translate", json={"text": "救命"})
        assert resp.status_code == 200
        data = resp.json()
        assert data["target_lang"] == "en"


# ---------------------------------------------------------------------------
# GET /models – list available models
# ---------------------------------------------------------------------------

class TestModels:
    def test_list_models_returns_registry(self, client):
        resp = client.get("/models")
        assert resp.status_code == 200
        data = resp.json()
        assert "active" in data
        assert "models" in data
        names = [m["name"] for m in data["models"]]
        assert names == ["gemma4-linkguard2.0"]
        assert data["active"] == "gemma4-linkguard2.0"

    def test_list_models_shows_active(self, client):
        resp = client.get("/models")
        data = resp.json()
        active_entries = [m for m in data["models"] if m["active"]]
        assert len(active_entries) == 1

    def test_each_model_has_description(self, client):
        resp = client.get("/models")
        for m in resp.json()["models"]:
            assert "description" in m and len(m["description"]) > 0


# ---------------------------------------------------------------------------
# POST /model – switch active model
# ---------------------------------------------------------------------------

class TestModelSwitch:
    def test_switch_to_gemma4_26b(self, client):
        # GEMMA4 26B 專用模式，允許同模型切換
        resp = client.post("/model", json={"model": "gemma4:26b"})
        assert resp.status_code == 200
        data = resp.json()
        assert data["active"] == "gemma4-linkguard2.0"
        assert "正式" in data["description"]
        # verify /model GET reflects new state
        get_resp = client.get("/model")
        assert get_resp.json()["active"] == "gemma4-linkguard2.0"

    def test_switch_to_legacy_gemma3_rejected(self, client):
        resp = client.post("/model", json={"model": "gemma3:4b"})
        assert resp.status_code == 400
        assert resp.json()["detail"]["code"] == "UNKNOWN_MODEL"

    def test_switch_back_to_default(self, client):
        resp = client.post("/model", json={"model": "gemma4:26b"})
        assert resp.json()["active"] == "gemma4-linkguard2.0"

    def test_switch_alias_to_gemma4_26b(self, client):
        resp = client.post("/model", json={"model": "GAMME"})
        assert resp.status_code == 200
        assert resp.json()["active"] == "gemma4-linkguard2.0"

    def test_switch_unknown_model_returns_error(self, client):
        resp = client.post("/model", json={"model": "nonexistent"})
        assert resp.status_code == 400
        data = resp.json()["detail"]
        assert data["status"] == "error"
        assert data["code"] == "UNKNOWN_MODEL"
        assert "nonexistent" in data["message"]

    def test_get_current_model(self, client):
        resp = client.get("/model")
        assert resp.status_code == 200
        data = resp.json()
        assert "active" in data
        assert "description" in data


# ---------------------------------------------------------------------------
# /generate includes model field
# ---------------------------------------------------------------------------

class TestGenerateModelField:
    @pytest.fixture()
    def mock_ollama(self):
        mock_response = MagicMock()
        mock_response.message.content = "【優先處置】測試"
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield mock_client_instance

    def test_generate_returns_model_field(self, client, tmp_db, mock_ollama):
        payload = {
            "voice_text": "test",
            "patients": [],
            "weather": {},
            "resources": "",
        }
        resp = client.post("/generate", json=payload)
        assert "model" in resp.json()

    def test_generate_uses_switched_model(self, client, tmp_db, mock_ollama):
        # 即使要求切換其他模型，仍固定使用 GEMMA4 26B
        client.post("/model", json={"model": "GAMME"})
        payload = {
            "voice_text": "test",
            "patients": [],
            "weather": {},
            "resources": "",
        }
        resp = client.post("/generate", json=payload)
        assert resp.json()["model"] == "gemma4-linkguard2.0"
        # verify chat was called with the gemma model
        mock_ollama.chat.assert_called()
        call_kwargs = mock_ollama.chat.call_args
        model_name = call_kwargs.kwargs.get("model") or call_kwargs[1].get("model")
        assert model_name == "gemma4:26b"


# ---------------------------------------------------------------------------
# /status — 系統狀態總覽
# ---------------------------------------------------------------------------

class TestSystemStatus:
    def test_status_returns_ok(self, client, tmp_db):
        resp = client.get("/status")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"

    def test_status_has_required_sections(self, client, tmp_db):
        resp = client.get("/status")
        data = resp.json()
        assert "model" in data
        assert "patients" in data
        assert "resources" in data
        assert "nodes" in data
        assert "auto_wake" in data
        assert "status_text" in data

    def test_status_model_info(self, client, tmp_db):
        resp = client.get("/status")
        model = resp.json()["model"]
        assert model["active"] == qwen_server.MODEL_NAME
        assert model["description"]

    def test_status_empty_db_defaults(self, client, tmp_db):
        resp = client.get("/status")
        data = resp.json()
        assert data["patients"]["total"] == 0
        assert data["active_queue"] == []
        assert data["nodes"] == []

    def test_status_text_contains_header(self, client, tmp_db):
        resp = client.get("/status")
        assert "【系統狀態】" in resp.json()["status_text"]

    def test_status_reflects_patient_data(self, client, tmp_db):
        """新增傷患後 /status 應反映統計資料。"""
        linkguard_db.save_patient({
            "patient_id": "P-TEST-001",
            "breathing_rate": 35,
            "capillary_refill": 3.0,
            "can_follow_commands": True,
            "device_id": "D1",
        })
        resp = client.get("/status")
        data = resp.json()
        assert data["patients"]["total"] >= 1


# ---------------------------------------------------------------------------
# /command — 指令發布
# ---------------------------------------------------------------------------

class TestCommand:
    def test_manual_command(self, client, tmp_db):
        resp = client.post("/command", json={
            "command_type": "dispatch",
            "priority": 1,
            "title": "派遣救護車到A區",
            "detail": "兩名紅色傷患需要緊急後送",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert "command" in data
        assert data["command"]["type"] == "dispatch"
        assert data["command"]["source"] == "manual"
        assert data["command"]["status"] == "pending"

    def test_manual_command_missing_title(self, client, tmp_db):
        resp = client.post("/command", json={
            "command_type": "dispatch",
            "priority": 1,
        })
        assert resp.status_code == 400

    def test_manual_command_invalid_type(self, client, tmp_db):
        resp = client.post("/command", json={
            "command_type": "invalid_type",
            "title": "test",
        })
        assert resp.status_code == 400

    def test_command_queue_starts_empty(self, client, tmp_db):
        qwen_server._command_queue.clear()
        resp = client.get("/command/queue")
        assert resp.status_code == 200
        assert resp.json()["total"] == 0

    def test_command_queue_accumulates(self, client, tmp_db):
        qwen_server._command_queue.clear()
        client.post("/command", json={
            "command_type": "alert",
            "priority": 2,
            "title": "餘震警報",
            "detail": "請所有單位注意",
        })
        client.post("/command", json={
            "command_type": "medical",
            "priority": 1,
            "title": "止血處理",
        })
        resp = client.get("/command/queue")
        assert resp.json()["total"] == 2

    @pytest.fixture()
    def mock_ollama_cmd(self):
        mock_response = MagicMock()
        mock_response.message.content = json.dumps({
            "commands": [{
                "type": "dispatch",
                "priority": 1,
                "title": "派遣救護車",
                "detail": "A區有紅色傷患",
                "targets": []
            }]
        })
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield

    def test_auto_generate_command(self, client, tmp_db, mock_ollama_cmd):
        qwen_server._command_queue.clear()
        resp = client.post("/command", json={
            "situation": "A區發現兩名紅色傷患，救護車尚未派遣",
            "auto_generate": True,
        })
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["commands"]) == 1
        assert data["commands"][0]["type"] == "dispatch"

    def test_command_ack(self, client, tmp_db):
        qwen_server._command_queue.clear()
        resp = client.post("/command", json={
            "command_type": "alert",
            "priority": 3,
            "title": "test ack",
        })
        cmd_id = resp.json()["command"]["id"]
        ack_resp = client.post("/command/ack", json={"command_id": cmd_id})
        assert ack_resp.status_code == 200
        # Verify status changed
        q = client.get("/command/queue")
        for c in q.json()["commands"]:
            if c["id"] == cmd_id:
                assert c["status"] == "executed"

    def test_command_ack_not_found(self, client, tmp_db):
        resp = client.post("/command/ack", json={"command_id": "nonexistent"})
        assert resp.status_code == 404


# ---------------------------------------------------------------------------
# /wake — 自動喚醒
# ---------------------------------------------------------------------------

class TestAutoWake:
    def test_wake_config_get(self, client, tmp_db):
        resp = client.get("/wake/config")
        assert resp.status_code == 200
        data = resp.json()
        assert "enabled" in data
        assert "interval_sec" in data

    def test_wake_config_set(self, client, tmp_db):
        resp = client.post("/wake/config", json={
            "enabled": False,
            "interval": 60,
        })
        assert resp.status_code == 200
        assert resp.json()["enabled"] is False
        assert resp.json()["interval_sec"] == 60
        # Restore
        qwen_server._autowake_enabled = True
        qwen_server.AUTOWAKE_INTERVAL = 120

    @pytest.fixture()
    def mock_ollama_wake(self):
        mock_response = MagicMock()
        mock_response.message.content = "【巡檢結果】正常\n【建議行動】持續監控"
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield

    def test_manual_wake(self, client, tmp_db, mock_ollama_wake):
        resp = client.post("/wake")
        assert resp.status_code == 200
        assert "已觸發" in resp.json()["message"]

    def test_manual_wake_saves_decision(self, client, tmp_db, mock_ollama_wake):
        resp = client.post("/wake")
        assert resp.status_code == 200
        decisions = linkguard_db.get_recent_decisions(1)
        assert len(decisions) >= 1
        assert "[自動喚醒]" in decisions[0]["voice_text"]


# ---------------------------------------------------------------------------
# _parse_command_json
# ---------------------------------------------------------------------------

class TestParseCommandJson:
    def test_parse_valid_json(self):
        raw = '{"commands": [{"type": "dispatch", "priority": 1, "title": "test"}]}'
        result = qwen_server._parse_command_json(raw)
        assert len(result) == 1
        assert result[0]["type"] == "dispatch"

    def test_parse_json_with_markdown_fence(self):
        raw = '```json\n{"commands": [{"type": "alert", "title": "test"}]}\n```'
        result = qwen_server._parse_command_json(raw)
        assert len(result) == 1

    def test_parse_empty_returns_empty(self):
        assert qwen_server._parse_command_json("") == []

    def test_parse_invalid_json_returns_empty(self):
        assert qwen_server._parse_command_json("not json at all") == []

    def test_parse_list_format(self):
        raw = '[{"type": "evacuate", "title": "撤離"}]'
        result = qwen_server._parse_command_json(raw)
        assert len(result) == 1


# ---------------------------------------------------------------------------
# _format_status_for_llm
# ---------------------------------------------------------------------------

class TestFormatStatusForLLM:
    def test_contains_header(self, tmp_db):
        text = qwen_server._format_status_for_llm()
        assert "【系統狀態】" in text

    def test_contains_patient_count(self, tmp_db):
        text = qwen_server._format_status_for_llm()
        assert "傷患總計" in text

    def test_contains_node_info(self, tmp_db):
        text = qwen_server._format_status_for_llm()
        assert "LoRa 節點" in text


# ---------------------------------------------------------------------------
# _check_wake_triggers
# ---------------------------------------------------------------------------

class TestWakeTriggers:
    def test_no_trigger_on_empty(self, tmp_db):
        qwen_server._prev_patient_hash = ""
        should, reason = qwen_server._check_wake_triggers()
        # First call sets hash, no trigger
        assert not should

    def test_trigger_on_red_patient(self, tmp_db):
        linkguard_db.save_patient({
            "patient_id": "P-RED-001",
            "breathing_rate": 35,
            "capillary_refill": 3.0,
            "can_follow_commands": True,
            "device_id": "D1",
        })
        # Update priority to red
        linkguard_db.update_patient_score(
            "P-RED-001", "紅色", "呼吸>30", 10.0, 85.0, "{}"
        )
        qwen_server._prev_patient_hash = "old_hash"
        should, reason = qwen_server._check_wake_triggers()
        assert should
        assert "紅色" in reason or "變化" in reason


# ---------------------------------------------------------------------------
# 雙模型功能測試
# ---------------------------------------------------------------------------

class TestParseConfidence:
    def test_parse_valid_confidence(self):
        text = "【優先處置】...\n【信心度】0.85 | 情況明確"
        score, reason = qwen_server._parse_confidence(text)
        assert score == 0.85
        assert reason == "情況明確"

    def test_parse_low_confidence(self):
        text = "【優先處置】...\n【信心度】0.30 | 資源不足"
        score, reason = qwen_server._parse_confidence(text)
        assert score == 0.30
        assert reason == "資源不足"

    def test_parse_missing_confidence_defaults(self):
        text = "【優先處置】一般處理"
        score, reason = qwen_server._parse_confidence(text)
        assert score == 0.5
        assert "未輸出" in reason

    def test_parse_fullwidth_pipe(self):
        text = "【信心度】0.72 ｜ 多重傷患"
        score, reason = qwen_server._parse_confidence(text)
        assert score == 0.72
        assert reason == "多重傷患"

    def test_parse_clamps_to_range(self):
        text = "【信心度】1.5 | 超出範圍"
        score, _ = qwen_server._parse_confidence(text)
        assert score == 1.0

    def test_parse_negative_returns_default(self):
        """負值不匹配正則，回傳預設 0.5。"""
        text = "【信心度】-0.3 | 負值"
        score, _ = qwen_server._parse_confidence(text)
        assert score == 0.5


class TestStripConfidenceLine:
    def test_removes_confidence_line(self):
        text = "【優先處置】ABC\n【信心度】0.80 | 正常"
        result = qwen_server._strip_confidence_line(text)
        assert "【信心度】" not in result
        assert "【優先處置】ABC" in result

    def test_no_confidence_line_unchanged(self):
        text = "【優先處置】ABC\n【注意事項】DEF"
        result = qwen_server._strip_confidence_line(text)
        assert result == text


class TestShouldEscalate:
    @pytest.fixture(autouse=True)
    def setup_dual(self):
        """暫時啟用雙模型 small 角色。"""
        original = dict(qwen_server.DUAL_CFG)
        qwen_server.DUAL_CFG.update({
            "enabled": True,
            "local_role": "small",
            "always_escalate": False,  # 測試規則式判斷時關閉一律升級
            "confidence_threshold": 0.6,
            "escalation_rules": {
                "min_red_patients_for_auto_escalate": 3,
                "resource_utilization_threshold": 0.8,
                "always_escalate_evacuation": True,
            },
        })
        yield
        qwen_server.DUAL_CFG.clear()
        qwen_server.DUAL_CFG.update(original)

    def test_low_confidence_escalates(self):
        assert qwen_server._should_escalate(0.3, [], "") is True

    def test_high_confidence_no_escalate(self):
        assert qwen_server._should_escalate(0.8, [], "") is False

    def test_threshold_boundary_no_escalate(self):
        assert qwen_server._should_escalate(0.6, [], "") is False

    def test_many_red_patients_escalates(self):
        ranked = [{"priority": "紅色"} for _ in range(3)]
        assert qwen_server._should_escalate(0.7, ranked, "") is True

    def test_few_red_patients_no_escalate(self):
        ranked = [{"priority": "紅色"}, {"priority": "紅色"}]
        assert qwen_server._should_escalate(0.7, ranked, "") is False

    def test_zero_resource_escalates(self):
        assert qwen_server._should_escalate(0.7, [], "醫療包 0/5") is True

    def test_disabled_never_escalates(self):
        qwen_server.DUAL_CFG["enabled"] = False
        assert qwen_server._should_escalate(0.1, [], "0/5") is False

    def test_large_role_never_escalates(self):
        qwen_server.DUAL_CFG["local_role"] = "large"
        assert qwen_server._should_escalate(0.1, [], "0/5") is False

    def test_resource_utilization_above_threshold_escalates(self):
        """資源使用率 >= 0.8 → 升級"""
        # 醫療包 1/5 → utilization = (5-1)/5 = 0.8, 擔架 1/3 → (3-1)/3 = 0.67
        assert qwen_server._should_escalate(0.8, [], "醫療包 1/5, 擔架 1/3") is True

    def test_resource_utilization_below_threshold_no_escalate(self):
        """資源使用率 < 0.8 → 不升級"""
        # 醫療包 3/5 → utilization = (5-3)/5 = 0.4
        assert qwen_server._should_escalate(0.8, [], "醫療包 3/5") is False

    def test_resource_utilization_no_rule_no_escalate(self):
        """未設定 resource_utilization_threshold → 不因使用率升級"""
        del qwen_server.DUAL_CFG["escalation_rules"]["resource_utilization_threshold"]
        assert qwen_server._should_escalate(0.8, [], "醫療包 1/5") is False

    def test_evacuation_decision_always_escalates(self):
        """涉及撤離的決策永遠升級"""
        assert qwen_server._should_escalate(0.8, [], "", "立即撤離所有人員") is True

    def test_evacuation_keywords_all_match(self):
        """全部撤離關鍵字皆觸發升級"""
        for kw in ("撤離", "撤退", "疏散", "避難", "緊急轉移"):
            assert qwen_server._should_escalate(0.8, [], "", f"建議{kw}至安全區") is True

    def test_non_evacuation_decision_no_escalate(self):
        """不含撤離關鍵字的決策不觸發升級"""
        assert qwen_server._should_escalate(0.8, [], "", "繼續搜救作業") is False

    def test_evacuation_disabled_no_escalate(self):
        """always_escalate_evacuation=False 時不因撤離升級"""
        qwen_server.DUAL_CFG["escalation_rules"]["always_escalate_evacuation"] = False
        assert qwen_server._should_escalate(0.8, [], "", "立即撤離") is False


class TestDualEndpoints:
    @pytest.fixture(autouse=True)
    def setup_dual_cfg(self):
        original = dict(qwen_server.DUAL_CFG)
        yield
        qwen_server.DUAL_CFG.clear()
        qwen_server.DUAL_CFG.update(original)

    def test_peer_ping(self, client, tmp_db):
        qwen_server.DUAL_CFG["enabled"] = True
        qwen_server.DUAL_CFG["local_role"] = "large"
        resp = client.get("/peer/ping")
        assert resp.status_code == 200
        data = resp.json()
        assert data["role"] == "large"
        assert data["dual_enabled"] is True

    def test_get_dual_config(self, client, tmp_db):
        resp = client.get("/dual/config")
        assert resp.status_code == 200
        assert "dual" in resp.json()

    def test_update_dual_config(self, client, tmp_db):
        resp = client.post("/dual/config", json={
            "enabled": True,
            "local_role": "small",
            "confidence_threshold": 0.7,
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["dual"]["enabled"] is True
        assert data["dual"]["local_role"] == "small"
        assert data["dual"]["confidence_threshold"] == 0.7

    def test_update_invalid_role_rejected(self, client, tmp_db):
        resp = client.post("/dual/config", json={"local_role": "invalid"})
        assert resp.status_code == 400

    def test_update_invalid_threshold_rejected(self, client, tmp_db):
        resp = client.post("/dual/config", json={"confidence_threshold": 1.5})
        assert resp.status_code == 400

    def test_dual_status(self, client, tmp_db):
        qwen_server.DUAL_CFG["enabled"] = True
        qwen_server.DUAL_CFG["local_role"] = "small"
        resp = client.get("/dual/status")
        assert resp.status_code == 200
        data = resp.json()
        assert data["enabled"] is True
        assert data["local_role"] == "small"
        assert "peer_alive" in data

    def test_status_includes_dual_model(self, client, tmp_db):
        """GET /status 應包含 dual_model 欄位。"""
        qwen_server.DUAL_CFG["enabled"] = True
        qwen_server.DUAL_CFG["local_role"] = "small"
        resp = client.get("/status")
        data = resp.json()
        assert "dual_model" in data
        assert data["dual_model"]["enabled"] is True


class TestEscalateEndpoint:
    """V2 異步升級語義：/escalate 立即回 202 + queue_position，背景跑大模型 + callback。"""

    @pytest.fixture(autouse=True)
    def setup_large_role(self):
        original = dict(qwen_server.DUAL_CFG)
        qwen_server.DUAL_CFG.update({
            "enabled": True,
            "local_role": "large",
            "local_model": "gemma4:26b",
        })
        yield
        qwen_server.DUAL_CFG.clear()
        qwen_server.DUAL_CFG.update(original)

    @pytest.fixture()
    def mock_ollama_escalate(self):
        mock_response = MagicMock()
        mock_response.message.content = "【優先處置】深度分析：應增派人員"
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield

    def test_escalate_returns_202_with_queue_position(self, client, tmp_db, mock_ollama_escalate):
        """/escalate 立即回 202 + queue_position，不阻塞。"""
        payload = {
            "request_id": "ESC-TEST-001",
            "callback_url": "",
            "original_request": {
                "voice_text": "現場混亂",
                "patients": [
                    {"id": "P1", "breathing_rate": 35, "capillary_refill": 3.0,
                     "can_follow_commands": False}
                ],
                "weather": {"temperature": 30},
                "resources": "醫療包 0/5",
            },
            "small_model_result": {
                "decision": "【優先處置】初判：派遣救護",
                "confidence": 0.3,
                "confidence_reason": "資源極度不足",
                "model": "gemma4:e4b",
            },
            "escalation_trigger": "confidence_below_threshold",
            "system_status": {},
        }
        resp = client.post("/escalate", json=payload)
        assert resp.status_code == 202
        body = resp.json()
        data = body.get("data", body)
        assert data["request_id"] == "ESC-TEST-001"
        assert data["queued"] is True
        assert data["queue_position"] >= 1

    def test_escalate_rejected_when_not_large_role(self, client, tmp_db, mock_ollama_escalate):
        """小模型節點收到 /escalate 應回 400。"""
        qwen_server.DUAL_CFG["local_role"] = "small"
        payload = {
            "request_id": "ESC-TEST-003",
            "original_request": {"voice_text": "x", "patients": [], "weather": {}, "resources": ""},
            "small_model_result": {"decision": "x", "confidence": 0.2, "confidence_reason": "", "model": "gemma4:e4b"},
        }
        resp = client.post("/escalate", json=payload)
        assert resp.status_code == 400


class TestGenerateWithDualModel:
    """測試 /generate 在雙模型 small 角色下的升級行為（V2 非阻塞 + provisional）。"""

    @pytest.fixture(autouse=True)
    def setup_dual_small(self):
        original = dict(qwen_server.DUAL_CFG)
        qwen_server.DUAL_CFG.update({
            "enabled": True,
            "local_role": "small",
            "local_model": "gemma4:e4b",
            "peer_host": "127.0.0.1",
            "peer_port": 8001,
            "always_escalate": False,  # 用規則式驗證行為
            "confidence_threshold": 0.6,
            "escalation_rules": {
                "min_red_patients_for_auto_escalate": 3,
            },
        })
        yield
        qwen_server.DUAL_CFG.clear()
        qwen_server.DUAL_CFG.update(original)

    @pytest.fixture()
    def mock_ollama_high_conf(self):
        """小模型回傳高信心度決策。"""
        mock_response = MagicMock()
        mock_response.message.content = (
            "【優先處置】派遣救護車\n"
            "【信心度】0.85 | 情況明確標準處置"
        )
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield

    def test_high_confidence_no_escalation(self, client, tmp_db, mock_ollama_high_conf):
        payload = {
            "voice_text": "一名輕傷",
            "patients": [{"id": "P1", "breathing_rate": 18, "capillary_refill": 1.0,
                          "can_follow_commands": True}],
            "weather": {},
            "resources": "醫療包 3/5",
        }
        resp = client.post("/generate", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["escalated"] is False
        # 信心度行應被移除
        assert "【信心度】" not in data["decision"]
        assert "【優先處置】" in data["decision"]

    @pytest.fixture()
    def mock_ollama_low_conf(self):
        """小模型回傳低信心度。"""
        mock_response = MagicMock()
        mock_response.message.content = (
            "【優先處置】不確定\n"
            "【信心度】0.30 | 資源極度不足"
        )
        mock_client_instance = MagicMock()
        mock_client_instance.chat.return_value = mock_response
        with patch("gemma4_server.ollama.Client", return_value=mock_client_instance):
            yield

    def test_low_confidence_peer_offline_fallback(self, client, tmp_db, mock_ollama_low_conf):
        """對端離線時，低信心度仍回傳小模型結果。"""
        qwen_server._peer_alive = False
        payload = {
            "voice_text": "多名傷患",
            "patients": [],
            "weather": {},
            "resources": "醫療包 0/5",
        }
        resp = client.post("/generate", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["escalated"] is False
        assert "【信心度】" not in data["decision"]

