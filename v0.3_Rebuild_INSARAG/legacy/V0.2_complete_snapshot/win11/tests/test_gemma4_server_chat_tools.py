"""
Tests for gemma4_server.py /chat/with_tools endpoint and helpers
(_split_reply_and_proposals, _build_tools_system_prompt).

Ollama is stubbed; no real LLM is invoked.
"""
import sys
import os
import pytest
from unittest.mock import patch, MagicMock

# Stub ollama before importing gemma4_server
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
    db_dir = str(tmp_path / "data")
    db_path = os.path.join(db_dir, "linkguard.db")
    with patch.object(linkguard_db, "DB_DIR", db_dir), \
         patch.object(linkguard_db, "DB_PATH", db_path):
        linkguard_db.init_db()
        yield db_path


@pytest.fixture()
def client(tmp_db):
    return TestClient(qwen_server.app, raise_server_exceptions=True)


def _mock_chat(content: str):
    """Patch ollama.Client to return a fake chat response with given content."""
    resp = MagicMock()
    resp.message.content = content
    inst = MagicMock()
    inst.chat.return_value = resp
    return patch("gemma4_server.ollama.Client", return_value=inst)


# ---------------------------------------------------------------------------
# _split_reply_and_proposals helper
# ---------------------------------------------------------------------------

class TestSplitReplyAndProposals:
    def test_no_json_returns_text_and_empty_list(self):
        reply, props = qwen_server._split_reply_and_proposals(
            "請指揮官評估後再行動。"
        )
        assert reply == "請指揮官評估後再行動。"
        assert props == []

    def test_empty_input(self):
        reply, props = qwen_server._split_reply_and_proposals("")
        assert reply == ""
        assert props == []

    def test_fenced_json_extracted(self):
        raw = (
            "建議立即派遣搜救隊前往 B 棟。\n\n"
            "```json\n"
            '{"proposals":[{"type":"dispatch","priority":1,'
            '"title":"派遣搜救隊到 B 棟","detail":"3 樓有人受困",'
            '"targets":[],"rationale":"紅色傷患需立即處置"}]}\n'
            "```"
        )
        reply, props = qwen_server._split_reply_and_proposals(raw)
        assert "派遣搜救隊" in reply
        assert "```" not in reply  # JSON block stripped
        assert len(props) == 1
        p = props[0]
        assert p["type"] == "dispatch"
        assert p["priority"] == 1
        assert p["title"] == "派遣搜救隊到 B 棟"
        assert p["detail"] == "3 樓有人受困"
        assert p["targets"] == []
        assert p["rationale"] == "紅色傷患需立即處置"
        assert p["id"].startswith("AIP-")
        assert "timestamp" in p

    def test_invalid_json_returns_no_proposals(self):
        raw = "回覆內容\n```json\n{not valid json}\n```"
        reply, props = qwen_server._split_reply_and_proposals(raw)
        assert props == []
        # 無法解析時 fenced block 仍視為 JSON 候選 → 不剝除（避免誤刪）
        # 至少 reply 不為空，且不應 crash
        assert reply  # 仍含原文

    def test_invalid_type_filtered_out(self):
        raw = (
            "```json\n"
            '{"proposals":[{"type":"unknown","title":"X","priority":2}]}\n'
            "```"
        )
        _, props = qwen_server._split_reply_and_proposals(raw)
        assert props == []

    def test_missing_title_filtered_out(self):
        raw = (
            "```json\n"
            '{"proposals":[{"type":"alert","title":"","priority":2}]}\n'
            "```"
        )
        _, props = qwen_server._split_reply_and_proposals(raw)
        assert props == []

    def test_priority_clamped_to_range(self):
        raw = (
            "```json\n"
            '{"proposals":['
            '{"type":"alert","title":"高","priority":99},'
            '{"type":"alert","title":"低","priority":-3},'
            '{"type":"alert","title":"無","priority":"abc"}'
            ']}\n```'
        )
        _, props = qwen_server._split_reply_and_proposals(raw)
        assert len(props) == 3
        assert props[0]["priority"] == 5
        assert props[1]["priority"] == 1
        assert props[2]["priority"] == 3  # default fallback

    def test_max_three_proposals(self):
        items = ",".join(
            f'{{"type":"alert","title":"T{i}","priority":2}}' for i in range(10)
        )
        raw = f"```json\n{{\"proposals\":[{items}]}}\n```"
        _, props = qwen_server._split_reply_and_proposals(raw)
        assert len(props) == 3

    def test_targets_normalised_to_strings(self):
        raw = (
            "```json\n"
            '{"proposals":[{"type":"medical","title":"後送","priority":2,'
            '"targets":["A001",123,"  ",""," B002 "]}]}\n```'
        )
        _, props = qwen_server._split_reply_and_proposals(raw)
        assert props[0]["targets"] == ["A001", "123", "B002"]

    def test_all_six_types_accepted(self):
        for t in ("dispatch", "alert", "evacuate", "medical", "resource", "personnel"):
            raw = f'```json\n{{"proposals":[{{"type":"{t}","title":"X","priority":2}}]}}\n```'
            _, props = qwen_server._split_reply_and_proposals(raw)
            assert len(props) == 1, f"type {t} should be accepted"
            assert props[0]["type"] == t

    def test_bare_json_without_fence(self):
        raw = '{"proposals":[{"type":"alert","title":"撤離","priority":1}]}'
        reply, props = qwen_server._split_reply_and_proposals(raw)
        assert len(props) == 1
        assert props[0]["title"] == "撤離"
        assert reply == ""


# ---------------------------------------------------------------------------
# /chat/with_tools endpoint
# ---------------------------------------------------------------------------

class TestChatWithToolsEndpoint:
    def test_empty_message_returns_empty_proposals(self, client):
        resp = client.post("/chat/with_tools", json={"message": ""})
        assert resp.status_code == 200
        body = resp.json()
        assert body["reply"] == ""
        assert body["proposals"] == []

    def test_text_only_reply_no_proposals(self, client):
        with _mock_chat("資訊不足，請補充傷患數量與位置。"):
            resp = client.post("/chat/with_tools", json={"message": "如何處置？"})
        assert resp.status_code == 200
        body = resp.json()
        assert "資訊不足" in body["reply"]
        assert body["proposals"] == []
        assert "model" in body
        assert "elapsed_ms" in body

    def test_with_proposals_extracted(self, client):
        ai_text = (
            "建議立即執行兩項行動。\n\n"
            "```json\n"
            '{"proposals":['
            '{"type":"dispatch","priority":1,"title":"派遣A隊到B棟",'
            '"detail":"B棟3F有3人受困","targets":[],"rationale":"紅色傷患"},'
            '{"type":"medical","priority":2,"title":"準備醫療後送",'
            '"detail":"集結點需2台救護車","targets":[],"rationale":"傷患數量多"}'
            ']}\n```'
        )
        with _mock_chat(ai_text):
            resp = client.post("/chat/with_tools", json={
                "message": "B棟2F倒塌，3名傷患"
            })
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["proposals"]) == 2
        assert body["proposals"][0]["type"] == "dispatch"
        assert body["proposals"][1]["type"] == "medical"
        assert "建議立即執行兩項行動" in body["reply"]
        assert "```" not in body["reply"]

    def test_ollama_connection_error_returns_503(self, client):
        inst = MagicMock()
        inst.chat.side_effect = ConnectionError("offline")
        with patch("gemma4_server.ollama.Client", return_value=inst):
            resp = client.post("/chat/with_tools", json={"message": "hi"})
        assert resp.status_code == 503

    def test_history_passed_through(self, client):
        captured = {}

        def fake_chat(**kwargs):
            captured["messages"] = kwargs.get("messages")
            r = MagicMock()
            r.message.content = "OK"
            return r

        inst = MagicMock()
        inst.chat.side_effect = fake_chat
        with patch("gemma4_server.ollama.Client", return_value=inst):
            resp = client.post("/chat/with_tools", json={
                "message": "下一步？",
                "history": [
                    {"role": "user", "content": "現況如何？"},
                    {"role": "assistant", "content": "B棟有 3 人受困"},
                ],
            })
        assert resp.status_code == 200
        msgs = captured["messages"]
        # system + 2 history + 1 current user
        assert len(msgs) == 4
        assert msgs[0]["role"] == "system"
        # system prompt 應含 tool 指令說明
        assert "AI 副駕駛指令模式" in msgs[0]["content"]
        assert msgs[-1]["content"] == "下一步？"
