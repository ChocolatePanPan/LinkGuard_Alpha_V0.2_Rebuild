"""
Tests for Phase 2+3 features: time sync, delivery tracking, and msg_id generation
in tcp_server.py.
"""
import sys
import os
import json
import asyncio
import itertools
import time
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------------------------
# Stub heavy dependencies before importing tcp_server
# ---------------------------------------------------------------------------
zeroconf_stub = MagicMock()
sys.modules.setdefault("zeroconf", zeroconf_stub)
paho_stub = MagicMock()
sys.modules.setdefault("paho", paho_stub)
sys.modules.setdefault("paho.mqtt", paho_stub.mqtt)
sys.modules.setdefault("paho.mqtt.client", paho_stub.mqtt.client)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import tcp_server
from utils import generate_msg_id


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_writer() -> MagicMock:
    writer = MagicMock(spec=asyncio.StreamWriter)
    writer.write = MagicMock()
    writer.drain = AsyncMock()
    return writer


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def reset_state():
    tcp_server.connected_clients.clear()
    tcp_server.patient_queue.clear()
    tcp_server.device_locations.clear()
    tcp_server.current_voice = ""
    tcp_server.last_weather = {}
    tcp_server.message_read_tracker.clear()
    tcp_server._broadcast_counter = itertools.count(1)
    if hasattr(tcp_server, '_warned_patients'):
        tcp_server._warned_patients.clear()
    if hasattr(tcp_server, 'active_sos'):
        tcp_server.active_sos.clear()
    if hasattr(tcp_server, 'device_clock_offsets'):
        tcp_server.device_clock_offsets.clear()
    if hasattr(tcp_server, 'delivery_tracking'):
        tcp_server.delivery_tracking.clear()
    yield


# ---------------------------------------------------------------------------
# make_msg with msg_id
# ---------------------------------------------------------------------------

class TestMakeMsgWithId:
    def test_msg_id_included_when_provided(self):
        msg = tcp_server.make_msg("decision", {"result": "go"}, msg_id="DEC-20260101-abc12345")
        assert msg["msg_id"] == "DEC-20260101-abc12345"

    def test_msg_id_absent_when_not_provided(self):
        msg = tcp_server.make_msg("pong", {"key": "val"})
        assert "msg_id" not in msg


# ---------------------------------------------------------------------------
# time_sync handler
# ---------------------------------------------------------------------------

class TestTimeSync:
    @pytest.mark.asyncio
    async def test_time_sync_stores_offset(self):
        writer = _make_writer()
        # Simulate client sending its time (slightly behind server)
        client_time = datetime.now(timezone(timedelta(hours=8))).isoformat()
        msg = {
            "type": "time_sync",
            "device_id": "dev1",
            "data": {"client_time": client_time},
        }
        await tcp_server.handle_message(msg, writer)
        assert "dev1" in tcp_server.device_clock_offsets

    @pytest.mark.asyncio
    async def test_time_sync_sends_response(self):
        writer = _make_writer()
        client_time = datetime.now(timezone(timedelta(hours=8))).isoformat()
        msg = {
            "type": "time_sync",
            "device_id": "dev1",
            "data": {"client_time": client_time},
        }
        await tcp_server.handle_message(msg, writer)
        writer.write.assert_called_once()
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "time_sync_response"
        assert "server_time" in sent["data"]
        assert "offset_ms" in sent["data"]

    @pytest.mark.asyncio
    async def test_offset_is_integer(self):
        writer = _make_writer()
        client_time = datetime.now(timezone(timedelta(hours=8))).isoformat()
        msg = {
            "type": "time_sync",
            "device_id": "dev1",
            "data": {"client_time": client_time},
        }
        await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert isinstance(sent["data"]["offset_ms"], int)


# ---------------------------------------------------------------------------
# delivery_ack handler
# ---------------------------------------------------------------------------

class TestDeliveryAck:
    @pytest.mark.asyncio
    async def test_delivery_ack_updates_tracking(self):
        # Setup: create a delivery tracking entry
        msg_id = "DEC-20260101-test0001"
        tcp_server.delivery_tracking[msg_id] = {
            "msg": {"type": "decision", "msg_id": msg_id},
            "targets": {"dev1", "dev2"},
            "delivered": set(),
            "retries": 0,
            "created_at": time.monotonic(),
        }
        writer = _make_writer()
        msg = {
            "type": "delivery_ack",
            "device_id": "dev1",
            "data": {"msg_id": msg_id},
        }
        with patch("tcp_server.broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        assert "dev1" in tcp_server.delivery_tracking[msg_id]["delivered"]

    @pytest.mark.asyncio
    async def test_delivery_ack_broadcasts_status(self):
        msg_id = "DEC-20260101-test0002"
        tcp_server.delivery_tracking[msg_id] = {
            "msg": {"type": "decision", "msg_id": msg_id},
            "targets": {"dev1"},
            "delivered": set(),
            "retries": 0,
            "created_at": time.monotonic(),
        }
        writer = _make_writer()
        msg = {
            "type": "delivery_ack",
            "device_id": "dev1",
            "data": {"msg_id": msg_id},
        }
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_bc:
            await tcp_server.handle_message(msg, writer)
        mock_bc.assert_awaited_once()
        bc_msg = mock_bc.call_args[0][0]
        assert bc_msg["type"] == "delivery_status"

    @pytest.mark.asyncio
    async def test_delivery_ack_unknown_msg_id_ignored(self):
        writer = _make_writer()
        msg = {
            "type": "delivery_ack",
            "device_id": "dev1",
            "data": {"msg_id": "NONEXISTENT-ID"},
        }
        # Should not raise
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_bc:
            await tcp_server.handle_message(msg, writer)
        mock_bc.assert_not_awaited()


# ---------------------------------------------------------------------------
# Pong includes server_time and uptime
# ---------------------------------------------------------------------------

class TestPongExtended:
    @pytest.mark.asyncio
    async def test_pong_includes_server_time(self):
        writer = _make_writer()
        msg = {"type": "ping", "device_id": "dev1", "data": {}}
        await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert "server_time" in sent["data"]
        assert "uptime_seconds" in sent["data"]
