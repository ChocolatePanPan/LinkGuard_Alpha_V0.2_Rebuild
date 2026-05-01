"""
Integration tests for gemma4_server.py — requires a running Ollama instance.

Usage:
    # Run only integration tests:
    python -m pytest tests/test_qwen_integration.py -v

    # Skip integration tests (default when Ollama is not running):
    Tests are auto-skipped if Ollama at OLLAMA_HOST is unreachable.

Environment variables:
    OLLAMA_HOST  — Ollama server URL (default: http://localhost:11434)
    QWEN_TEST_MODEL — Model to test with (default: linkguard-qwen)
"""
import os
import sys
import pytest
import httpx

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
TEST_MODEL = os.getenv("QWEN_TEST_MODEL", "gemma4:26b")


def _ollama_available() -> bool:
    """Check whether Ollama is reachable."""
    try:
        r = httpx.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        return r.status_code == 200
    except Exception:
        return False


def _model_available(model_name: str) -> bool:
    """Check whether a specific model is loaded in Ollama."""
    try:
        r = httpx.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        if r.status_code != 200:
            return False
        models = [m["name"] for m in r.json().get("models", [])]
        # Match with or without :latest tag
        return any(
            m == model_name or m.startswith(f"{model_name}:")
            for m in models
        )
    except Exception:
        return False


ollama_running = pytest.mark.skipif(
    not _ollama_available(),
    reason=f"Ollama not reachable at {OLLAMA_HOST}",
)

model_loaded = pytest.mark.skipif(
    not _model_available(TEST_MODEL),
    reason=f"Model '{TEST_MODEL}' not available in Ollama",
)


# ---------------------------------------------------------------------------
# Direct Ollama API tests (no FastAPI, pure model validation)
# ---------------------------------------------------------------------------

@ollama_running
@model_loaded
class TestOllamaDirectAPI:
    """Test Qwen model directly via Ollama REST API."""

    def test_model_responds(self):
        """Model should return a non-empty response to a simple prompt."""
        resp = httpx.post(
            f"{OLLAMA_HOST}/api/chat",
            json={
                "model": TEST_MODEL,
                "messages": [{"role": "user", "content": "回覆OK"}],
                "stream": False,
                "think": False,
                "options": {"num_predict": 32, "temperature": 0.1},
            },
            timeout=300,
        )
        assert resp.status_code == 200
        body = resp.json()
        content = body.get("message", {}).get("content", "")
        assert len(content.strip()) > 0, "Model returned empty response"

    def test_model_triage_prompt(self):
        """Model should produce a triage-related answer when given a rescue scenario."""
        prompt = (
            "你是災害救援指揮AI。現場一名傷患無呼吸，"
            "請依 START 檢傷分類標準判定其傷檢等級，只回答顏色和等級名稱。"
        )
        resp = httpx.post(
            f"{OLLAMA_HOST}/api/chat",
            json={
                "model": TEST_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
                "think": False,
                "options": {"num_predict": 64, "temperature": 0.1},
            },
            timeout=300,
        )
        assert resp.status_code == 200
        content = resp.json()["message"]["content"]
        # Expect the answer to mention 黑色 (DECEASED) for no-breathing patient
        assert "黑" in content, f"Expected '黑色' in response, got: {content}"

    def test_model_translation(self):
        """Model should be able to translate Chinese to English."""
        prompt = "將以下文字翻譯為英文，只輸出翻譯結果：傷患無法呼吸"
        resp = httpx.post(
            f"{OLLAMA_HOST}/api/chat",
            json={
                "model": TEST_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
                "think": False,
                "options": {"num_predict": 64, "temperature": 0.1},
            },
            timeout=300,
        )
        assert resp.status_code == 200
        content = resp.json()["message"]["content"].lower()
        # Should contain English words related to breathing
        assert any(
            word in content for word in ["breath", "patient", "unable"]
        ), f"Expected English translation, got: {content}"


# ---------------------------------------------------------------------------
# FastAPI integration tests (with real Ollama backend)
# ---------------------------------------------------------------------------

@ollama_running
@model_loaded
class TestQwenServerIntegration:
    """Test gemma4_server FastAPI endpoints with a real Ollama model."""

    @pytest.fixture(autouse=True)
    def _setup(self, tmp_path):
        """Patch DB to temp dir and create TestClient."""
        from unittest.mock import patch, MagicMock
        import linkguard_db
        from starlette.testclient import TestClient

        db_dir = str(tmp_path / "data")
        db_path = os.path.join(db_dir, "linkguard.db")

        # Ensure real ollama module is loaded (unit tests may have stubbed it)
        ollama_mod = sys.modules.get("ollama")
        if ollama_mod is None or isinstance(ollama_mod, MagicMock):
            if "ollama" in sys.modules:
                del sys.modules["ollama"]
            import ollama  # noqa: F811
            # Force gemma4_server to re-import if it was loaded with the stub
            if "gemma4_server" in sys.modules:
                import importlib
                importlib.reload(sys.modules["gemma4_server"])

            import gemma4_server as qwen_server
            qwen_server._active_model = TEST_MODEL

        with patch.object(linkguard_db, "DB_DIR", db_dir), \
             patch.object(linkguard_db, "DB_PATH", db_path):
            linkguard_db.init_db()
            self.client = TestClient(qwen_server.app, raise_server_exceptions=True)
            self.qwen_server = qwen_server
            yield
            qwen_server._active_model = qwen_server.MODEL_NAME

    def test_generate_returns_decision(self):
        """POST /generate should return a real LLM decision."""
        payload = {
            "voice_text": "現場三名傷患，一名無呼吸",
            "patients": [
                {
                    "id": "P1",
                    "breathing_rate": -1,
                    "capillary_refill": 0,
                    "can_follow_commands": False,
                },
                {
                    "id": "P2",
                    "breathing_rate": 22,
                    "capillary_refill": 1.5,
                    "can_follow_commands": True,
                },
            ],
            "weather": {
                "temperature": 32.0,
                "humidity": 80.0,
                "wind_speed": 3.0,
                "rainfall": 0.0,
            },
            "resources": "2名救護員, 1輛救護車",
        }
        resp = self.client.post("/generate", json=payload)
        assert resp.status_code == 200
        body = resp.json()
        assert "decision" in body
        assert len(body["decision"]) > 10, "Decision text too short"
        assert "patients" in body
        assert body["model"] == TEST_MODEL

    def test_generate_decision_saved_to_history(self):
        """Decision produced by /generate should appear in /history."""
        payload = {
            "voice_text": "測試整合",
            "patients": [],
            "weather": {},
            "resources": "",
        }
        self.client.post("/generate", json=payload)
        body = self.client.get("/history").json()
        history = body["history"]
        assert len(history) >= 1
        assert history[0]["voice_text"] == "測試整合"

    def test_translate_chinese_to_english(self):
        """POST /translate should produce English output."""
        resp = self.client.post("/translate", json={
            "text": "傷患需要緊急手術",
            "source_lang": "zh-TW",
            "target_lang": "en",
            "context": "medical",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["original"] == "傷患需要緊急手術"
        translated = data["translated"].lower()
        assert any(
            word in translated
            for word in ["patient", "surgery", "emergency", "urgent", "injur"]
        ), f"Translation doesn't seem English: {data['translated']}"

    def test_triage_score_single(self):
        """POST /triage/score should return scored patient."""
        resp = self.client.post("/triage/score", json={
            "patient": {
                "id": "P1",
                "breathing_rate": -1,
            },
        })
        assert resp.status_code == 200
        body = resp.json()
        assert body["priority"] == "黑色"

    def test_triage_rank_multiple(self):
        """POST /triage/rank should return sorted patient queue."""
        resp = self.client.post("/triage/rank", json={
            "patients": [
                {"id": "P1", "breathing_rate": 22, "capillary_refill": 1.5,
                 "can_follow_commands": True},
                {"id": "P2", "breathing_rate": 35, "capillary_refill": 3.0,
                 "can_follow_commands": False},
                {"id": "P3", "breathing_rate": -1},
            ],
        })
        assert resp.status_code == 200
        body = resp.json()
        assert body["count"] == 3
        priorities = [p["priority"] for p in body["queue"]]
        assert "黑色" in priorities
        assert "紅色" in priorities

    def test_model_list(self):
        """GET /models should list available models."""
        resp = self.client.get("/models")
        assert resp.status_code == 200
        data = resp.json()
        assert "models" in data
        assert "active" in data
        names = [m["name"] for m in data["models"]]
        assert TEST_MODEL in names
