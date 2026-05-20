"""
Plan v2 Phase A1.2 / A2 / A3 / A4 / A5 — three-tier routing & AI command tests.
Ollama is stubbed; no real LLM is invoked.
"""
import sys
import os
import asyncio
import pytest
from unittest.mock import patch, MagicMock

ollama_stub = MagicMock()
sys.modules.setdefault("ollama", ollama_stub)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import linkguard_db  # noqa: E402
import gemma4_server as qwen_server  # noqa: E402
from starlette.testclient import TestClient  # noqa: E402


@pytest.fixture()
def tmp_db(tmp_path):
    db_dir = str(tmp_path / "data")
    db_path = os.path.join(db_dir, "linkguard.db")
    with patch.object(linkguard_db, "DB_DIR", db_dir), \
         patch.object(linkguard_db, "DB_PATH", db_path):
        linkguard_db.init_db()
        yield db_path


@pytest.fixture()
def client(tmp_db):
    return TestClient(qwen_server.app, raise_server_exceptions=True)


# ---------------------------------------------------------------------------
# A1.2  tier helpers
# ---------------------------------------------------------------------------

class TestTierHelpers:
    def test_tiers_are_loaded(self):
        cfg = qwen_server.DUAL_CFG
        assert "tiers" in cfg
        for name in ("field", "hq_local", "hq_main"):
            assert name in cfg["tiers"]

    def test_resolve_tier_for_hq_session(self):
        assert qwen_server._resolve_tier_for_session("hq_commander") == "hq_main"

    def test_resolve_tier_for_field_session_default(self):
        assert qwen_server._resolve_tier_for_session("field_iphoneA") == "field"

    def test_resolve_tier_for_field_session_complex(self):
        assert qwen_server._resolve_tier_for_session("field_iphoneA", "complex") == "hq_local"

    def test_runtime_model_for_each_tier(self):
        assert qwen_server._runtime_model_for_tier("field") == "gemma4:e2b"
        assert qwen_server._runtime_model_for_tier("hq_local") == "gemma4:e4b"
        assert qwen_server._runtime_model_for_tier("hq_main") == "gemma4:26b"

    def test_thinking_mode_only_on_hq_main(self):
        assert qwen_server._tier_supports_thinking("hq_main") is True
        assert qwen_server._tier_supports_thinking("field") is False
        assert qwen_server._tier_supports_thinking("hq_local") is False


# ---------------------------------------------------------------------------
# A4  — proposal type registry
# ---------------------------------------------------------------------------

class TestProposalTypes:
    def test_16_types_registered(self):
        assert len(qwen_server._AI_PROPOSAL_TYPES) == 16

    def test_auto_types_exist(self):
        for name in ("dispatch", "status_check", "escalate_to_main",
                     "medical_priority_change", "resource_relocate", "recall", "checkpoint"):
            assert qwen_server._AI_PROPOSAL_META[name]["mode"] == "auto"

    def test_manual_types_exist(self):
        for name in ("alert", "medical", "resource", "personnel",
                     "evacuate", "emergency_evacuation", "force_broadcast",
                     "task_order", "zone_lockdown"):
            assert qwen_server._AI_PROPOSAL_META[name]["mode"] == "manual"

    def test_emergency_evacuation_requires_double_confirm(self):
        assert qwen_server._AI_PROPOSAL_META["emergency_evacuation"]["require_human_double_confirm"] is True
        assert qwen_server._AI_PROPOSAL_META["evacuate"]["require_human_double_confirm"] is True
        assert qwen_server._AI_PROPOSAL_META["zone_lockdown"]["require_human_double_confirm"] is True

    def test_dispatch_has_5s_countdown(self):
        assert qwen_server._AI_PROPOSAL_META["dispatch"]["countdown_sec"] == 5

    def test_status_check_no_countdown(self):
        assert qwen_server._AI_PROPOSAL_META["status_check"]["countdown_sec"] == 0


# ---------------------------------------------------------------------------
# A1.2 — /ai/health and /ai/models endpoints
# ---------------------------------------------------------------------------

class TestAIHealthEndpoints:
    def test_ai_models_returns_three_tiers(self, client):
        r = client.get("/ai/models")
        assert r.status_code == 200
        body = r.json()
        assert body["status"] == "ok"
        tiers = body["tiers"]
        assert set(tiers.keys()) == {"field", "hq_local", "hq_main"}
        assert tiers["hq_main"]["thinking_mode"] is True

    def test_ai_health_returns_tier_status(self, client):
        # patch httpx so it always returns 200 fake
        class _R:
            status_code = 200
        async def _fake_get(self, url):
            return _R()
        with patch("httpx.AsyncClient.get", _fake_get):
            r = client.get("/ai/health")
        assert r.status_code == 200
        body = r.json()
        assert body["status"] == "ok"
        for name in ("field", "hq_local", "hq_main"):
            assert body["tiers"][name]["ok"] is True


# ---------------------------------------------------------------------------
# A3 — propose / auto_dispatch / cancel command lifecycle
# ---------------------------------------------------------------------------

class TestAICommandLifecycle:
    def test_propose_auto_command_then_cancel(self, client):
        prop = {
            "type": "dispatch",
            "priority": 1,
            "title": "派遣搜救隊到 A 區",
            "detail": "兩名隊員前往集合點 A",
            "targets": [],
            "rationale": "Red 傷患三名",
        }
        r = client.post("/ai/command/propose", json={"proposal": prop})
        assert r.status_code == 200
        cmd = r.json()["command"]
        assert cmd["mode"] == "auto"
        assert cmd["countdown_sec"] == 5
        cmd_id = cmd["id"]

        # auto-dispatch with countdown
        r2 = client.post("/ai/command/auto_dispatch", json={"command_id": cmd_id})
        assert r2.status_code == 200
        assert r2.json()["status"] == "ok"

        # cancel before countdown elapses
        r3 = client.post(f"/ai/command/cancel/{cmd_id}")
        assert r3.status_code == 200
        assert r3.json()["status"] == "ok"

    def test_propose_manual_command_cannot_auto_dispatch(self, client):
        prop = {
            "type": "evacuate",
            "priority": 1,
            "title": "撤離 B 區",
            "detail": "因火勢蔓延",
            "targets": [],
        }
        r = client.post("/ai/command/propose", json={"proposal": prop})
        cmd_id = r.json()["command"]["id"]
        # evacuate is manual + double-confirm required → cannot auto_dispatch
        r2 = client.post("/ai/command/auto_dispatch", json={"command_id": cmd_id})
        assert r2.status_code in (400, 409)

    def test_propose_invalid_type_rejected(self, client):
        r = client.post("/ai/command/propose",
                        json={"proposal": {"type": "make_coffee", "title": "x"}})
        assert r.status_code == 400


# ---------------------------------------------------------------------------
# A5 — /report/formalize
# ---------------------------------------------------------------------------

class TestReportFormalize:
    def _mock_chat(self, content: str):
        resp = MagicMock()
        resp.message.content = content
        inst = MagicMock()
        inst.chat.return_value = resp
        return patch("gemma4_server.ollama.Client", return_value=inst)

    def test_formalize_field_report(self, client):
        with self._mock_chat(
            "[緊急程度: 黃]\n**事件**\n- 山林步道瓦斯桶外洩"
        ):
            r = client.post("/report/formalize", json={
                "raw_text": "我這邊看到瓦斯桶在漏氣，看起來不是大事但要處理",
                "reporter": "field_iphoneA",
                "incident_type": "hazard",
            })
        assert r.status_code == 200
        body = r.json()
        assert body["status"] == "ok"
        assert body["tier"] == "field"
        assert body["model"] == "gemma4:e2b"
        assert "瓦斯桶" in body["formal"]

    def test_empty_text_rejected(self, client):
        r = client.post("/report/formalize", json={"raw_text": "  "})
        assert r.status_code == 400
