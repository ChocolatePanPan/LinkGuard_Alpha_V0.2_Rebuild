"""
Tests for unified API response format (utils.py helpers)
and health check endpoints across all FastAPI services.
"""
import re
import time
import pytest
from unittest.mock import patch

import utils


# ---------------------------------------------------------------------------
# api_ok
# ---------------------------------------------------------------------------

class TestApiOk:
    def test_returns_status_ok(self):
        result = utils.api_ok()
        assert result["status"] == "ok"

    def test_contains_timestamp(self):
        result = utils.api_ok()
        assert "timestamp" in result
        assert "T" in result["timestamp"]

    def test_merges_data(self):
        result = utils.api_ok({"foo": "bar", "count": 42})
        assert result["foo"] == "bar"
        assert result["count"] == 42
        assert result["status"] == "ok"

    def test_none_data_omits_extras(self):
        result = utils.api_ok(None)
        assert set(result.keys()) == {"status", "timestamp"}

    def test_empty_dict_data_omits_extras(self):
        result = utils.api_ok({})
        assert set(result.keys()) == {"status", "timestamp"}


# ---------------------------------------------------------------------------
# api_error
# ---------------------------------------------------------------------------

class TestApiError:
    def test_raises_http_exception(self):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc_info:
            utils.api_error("TEST_CODE", "something went wrong")
        assert exc_info.value.status_code == 400
        detail = exc_info.value.detail
        assert detail["status"] == "error"
        assert detail["code"] == "TEST_CODE"
        assert detail["message"] == "something went wrong"

    def test_custom_status_code(self):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc_info:
            utils.api_error("NOT_FOUND", "missing", status_code=404)
        assert exc_info.value.status_code == 404

    def test_detail_contains_timestamp(self):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc_info:
            utils.api_error("X", "Y")
        assert "timestamp" in exc_info.value.detail


# ---------------------------------------------------------------------------
# generate_msg_id
# ---------------------------------------------------------------------------

class TestGenerateMsgId:
    def test_default_prefix(self):
        mid = utils.generate_msg_id()
        assert mid.startswith("MSG-")

    def test_custom_prefix(self):
        mid = utils.generate_msg_id("SOS")
        assert mid.startswith("SOS-")

    def test_format_pattern(self):
        mid = utils.generate_msg_id("DEC")
        # DEC-YYYYMMDD-xxxxxxxx
        assert re.match(r"^DEC-\d{8}-[0-9a-f]{8}$", mid)

    def test_unique_ids(self):
        ids = {utils.generate_msg_id("T") for _ in range(100)}
        assert len(ids) == 100


# ---------------------------------------------------------------------------
# health_check_response
# ---------------------------------------------------------------------------

class TestHealthCheckResponse:
    def test_contains_required_fields(self):
        resp = utils.health_check_response("test_service")
        assert resp["status"] == "ok"
        assert resp["service"] == "test_service"
        assert resp["version"] == "0.1"
        assert "uptime_seconds" in resp
        assert "timestamp" in resp

    def test_custom_version(self):
        resp = utils.health_check_response("svc", version="2.0")
        assert resp["version"] == "2.0"

    def test_extras_merged(self):
        resp = utils.health_check_response("svc", extras={"gpu": True})
        assert resp["gpu"] is True

    def test_uptime_is_non_negative(self):
        resp = utils.health_check_response("svc")
        assert resp["uptime_seconds"] >= 0
