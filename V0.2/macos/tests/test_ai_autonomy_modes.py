"""
Plan v2 Phase F — AI autonomy mode tests.

涵蓋：
  · 16 種指令的 mode/countdown/double_confirm 中繼資料
  · auto-dispatch 倒數立即執行 (countdown_sec=0 之 status_check / escalate_to_main)
  · auto-dispatch 倒數中取消
  · auto-dispatch 倒數結束自動派發
  · manual 提案不可走 auto_dispatch
  · double-confirm 必填類型不可走 auto_dispatch
  · 已派發 / 已取消狀態流轉防呆
  · 不存在 ID 的取消 / 派發
  · /ai/command/list 反映狀態變化

Ollama 與真實 LLM 不被呼叫；僅測試純規則層與 FastAPI endpoint。
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
    # 每測試清空 pending 字典，避免互相污染
    qwen_server._AI_PENDING_CMDS.clear()
    yield TestClient(qwen_server.app, raise_server_exceptions=True)
    qwen_server._AI_PENDING_CMDS.clear()


# ---------------------------------------------------------------------------
# Phase F1 — 中繼資料完整性
# ---------------------------------------------------------------------------

AUTO_TYPES = {
    "dispatch", "status_check", "escalate_to_main",
    "medical_priority_change", "resource_relocate", "recall", "checkpoint",
}
MANUAL_TYPES = {
    "alert", "medical", "resource", "personnel", "evacuate",
    "emergency_evacuation", "force_broadcast", "task_order", "zone_lockdown",
}
DOUBLE_CONFIRM_TYPES = {"emergency_evacuation", "zone_lockdown", "evacuate"}


class TestProposalMetaSet:
    def test_total_16_types(self):
        assert len(qwen_server._AI_PROPOSAL_META) == 16
        assert AUTO_TYPES | MANUAL_TYPES == set(qwen_server._AI_PROPOSAL_META.keys())

    @pytest.mark.parametrize("ptype", sorted(AUTO_TYPES))
    def test_auto_type_metadata(self, ptype):
        meta = qwen_server._AI_PROPOSAL_META[ptype]
        assert meta["mode"] == "auto"
        assert meta["countdown_sec"] >= 0
        assert meta["require_human_double_confirm"] is False

    @pytest.mark.parametrize("ptype", sorted(MANUAL_TYPES))
    def test_manual_type_metadata(self, ptype):
        meta = qwen_server._AI_PROPOSAL_META[ptype]
        assert meta["mode"] == "manual"

    @pytest.mark.parametrize("ptype", sorted(DOUBLE_CONFIRM_TYPES))
    def test_double_confirm_required(self, ptype):
        assert qwen_server._AI_PROPOSAL_META[ptype]["require_human_double_confirm"] is True


# ---------------------------------------------------------------------------
# Phase F2 — propose endpoint normalization
# ---------------------------------------------------------------------------

def _propose(client, ptype: str, **extra) -> dict:
    body = {"proposal": {"type": ptype, "priority": 3,
                          "title": f"test {ptype}", "detail": "x", **extra}}
    r = client.post("/ai/command/propose", json=body)
    assert r.status_code == 200, r.text
    return r.json()["command"]


class TestProposeNormalization:
    def test_propose_auto_carries_meta(self, client):
        cmd = _propose(client, "dispatch")
        assert cmd["mode"] == "auto"
        assert cmd["countdown_sec"] == 5
        assert cmd["require_human_double_confirm"] is False
        assert cmd["id"].startswith(("AIP-", "AIC-"))

    def test_propose_manual_carries_meta(self, client):
        cmd = _propose(client, "alert")
        assert cmd["mode"] == "manual"
        assert cmd["countdown_sec"] == 0

    def test_propose_double_confirm_carries_flag(self, client):
        cmd = _propose(client, "emergency_evacuation")
        assert cmd["mode"] == "manual"
        assert cmd["require_human_double_confirm"] is True

    def test_propose_unknown_type_400(self, client):
        r = client.post("/ai/command/propose",
                        json={"proposal": {"type": "make_coffee", "title": "x"}})
        assert r.status_code == 400


# ---------------------------------------------------------------------------
# Phase F3 — auto_dispatch & cancel state machine
# ---------------------------------------------------------------------------

class TestAutoDispatchStateMachine:
    def test_status_check_dispatches_immediately(self, client):
        cmd = _propose(client, "status_check")
        # countdown_sec == 0：scheduled 後馬上 dispatch
        r = client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        assert r.status_code == 200
        # 等待背景 task 完成（countdown=0 → 立即）
        async def _wait():
            for _ in range(20):
                if qwen_server._AI_PENDING_CMDS[cmd["id"]]["status"] == "dispatched":
                    return True
                await asyncio.sleep(0.05)
            return False
        ok = asyncio.get_event_loop().run_until_complete(_wait())
        assert ok, "command should have been dispatched within 1s"

    def test_dispatch_cancel_during_countdown(self, client):
        cmd = _propose(client, "dispatch")    # 5s countdown
        r1 = client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        assert r1.json()["command_status"] == "scheduled"
        # 立即取消
        r2 = client.post(f"/ai/command/cancel/{cmd['id']}")
        assert r2.status_code == 200
        assert r2.json()["command_status"] == "cancelled"
        # status 必須是 cancelled
        assert qwen_server._AI_PENDING_CMDS[cmd["id"]]["status"] == "cancelled"

    def test_manual_cannot_auto_dispatch(self, client):
        cmd = _propose(client, "alert")
        r = client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        assert r.status_code == 400
        assert "not_auto" in r.text or "auto-mode" in r.text

    def test_double_confirm_blocked_from_auto_dispatch(self, client):
        cmd = _propose(client, "emergency_evacuation")
        r = client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        # emergency_evacuation 是 manual，所以走 not_auto 路徑（先擋）；
        # 即使將來改為 auto，require_human_double_confirm 也會擋。
        assert r.status_code == 400

    def test_cannot_cancel_dispatched(self, client):
        cmd = _propose(client, "status_check")
        client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        async def _wait_dispatched():
            for _ in range(20):
                if qwen_server._AI_PENDING_CMDS[cmd["id"]]["status"] == "dispatched":
                    return True
                await asyncio.sleep(0.05)
            return False
        asyncio.get_event_loop().run_until_complete(_wait_dispatched())
        r = client.post(f"/ai/command/cancel/{cmd['id']}")
        assert r.status_code == 409

    def test_cancel_unknown_id_404(self, client):
        r = client.post("/ai/command/cancel/AIP-DOES-NOT-EXIST")
        assert r.status_code == 404

    def test_dispatch_unknown_id_404(self, client):
        r = client.post("/ai/command/auto_dispatch",
                        json={"command_id": "AIP-DOES-NOT-EXIST"})
        assert r.status_code == 404

    def test_cancel_twice_idempotent(self, client):
        cmd = _propose(client, "dispatch")
        client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        r1 = client.post(f"/ai/command/cancel/{cmd['id']}")
        r2 = client.post(f"/ai/command/cancel/{cmd['id']}")
        assert r1.status_code == 200 and r2.status_code == 200
        assert r2.json()["command_status"] == "cancelled"


# ---------------------------------------------------------------------------
# Phase F4 — /ai/command/list
# ---------------------------------------------------------------------------

class TestCommandList:
    def test_list_includes_proposed_command(self, client):
        cmd = _propose(client, "dispatch")
        r = client.get("/ai/command/list")
        assert r.status_code == 200
        ids = [c["id"] for c in r.json()["commands"]]
        assert cmd["id"] in ids

    def test_list_status_transitions(self, client):
        cmd = _propose(client, "dispatch")
        # 1) 初始 pending
        statuses = {c["id"]: c["command_status"] for c in client.get("/ai/command/list").json()["commands"]}
        assert statuses[cmd["id"]] == "pending"
        # 2) 排程後 scheduled
        client.post("/ai/command/auto_dispatch", json={"command_id": cmd["id"]})
        statuses = {c["id"]: c["command_status"] for c in client.get("/ai/command/list").json()["commands"]}
        assert statuses[cmd["id"]] == "scheduled"
        # 3) 取消後 cancelled
        client.post(f"/ai/command/cancel/{cmd['id']}")
        statuses = {c["id"]: c["command_status"] for c in client.get("/ai/command/list").json()["commands"]}
        assert statuses[cmd["id"]] == "cancelled"
