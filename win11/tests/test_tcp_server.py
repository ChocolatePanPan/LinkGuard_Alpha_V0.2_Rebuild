"""
Tests for tcp_server.py – utility functions and message handling logic.

zeroconf and paho are stubbed; network I/O is replaced by asyncio mocks.
"""
import sys
import os
import json
import asyncio
import pytest
from unittest.mock import MagicMock, AsyncMock, patch

# ---------------------------------------------------------------------------
# Stub heavy / unavailable dependencies before importing tcp_server
# ---------------------------------------------------------------------------
zeroconf_stub = MagicMock()
sys.modules.setdefault("zeroconf", zeroconf_stub)

paho_stub = MagicMock()
sys.modules.setdefault("paho", paho_stub)
sys.modules.setdefault("paho.mqtt", paho_stub.mqtt)
sys.modules.setdefault("paho.mqtt.client", paho_stub.mqtt.client)

# Stub linkguard_db to avoid real DB operations in unit tests
linkguard_db_stub = MagicMock()
sys.modules.setdefault("linkguard_db", linkguard_db_stub)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import tcp_server


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_writer() -> MagicMock:
    """Return a mock asyncio.StreamWriter."""
    writer = MagicMock(spec=asyncio.StreamWriter)
    writer.write = MagicMock()
    writer.drain = AsyncMock()
    return writer


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def reset_global_state():
    """Clear module-level state between tests."""
    tcp_server.connected_clients.clear()
    tcp_server.patient_queue.clear()
    tcp_server.device_locations.clear()
    tcp_server.current_voice = ""
    tcp_server.last_weather = {}
    tcp_server.message_read_tracker.clear()
    import itertools as _it
    tcp_server._broadcast_counter = _it.count(1)
    if hasattr(tcp_server, '_warned_patients'):
        tcp_server._warned_patients.clear()
    if hasattr(tcp_server, 'active_sos'):
        tcp_server.active_sos.clear()
    yield
    tcp_server.connected_clients.clear()
    tcp_server.patient_queue.clear()
    tcp_server.device_locations.clear()
    tcp_server.message_read_tracker.clear()
    tcp_server._broadcast_counter = _it.count(1)
    if hasattr(tcp_server, '_warned_patients'):
        tcp_server._warned_patients.clear()
    if hasattr(tcp_server, 'active_sos'):
        tcp_server.active_sos.clear()
    tcp_server.current_voice = ""
    tcp_server.last_weather = {}


# ---------------------------------------------------------------------------
# now_iso
# ---------------------------------------------------------------------------

class TestNowIso:
    def test_returns_string_with_timezone(self):
        ts = tcp_server.now_iso()
        assert isinstance(ts, str)
        assert "T" in ts


# ---------------------------------------------------------------------------
# make_msg
# ---------------------------------------------------------------------------

class TestMakeMsg:
    def test_structure(self):
        msg = tcp_server.make_msg("pong", {"key": "val"})
        assert msg["type"] == "pong"
        assert msg["device_id"] == "server"
        assert "timestamp" in msg
        assert msg["data"] == {"key": "val"}

    def test_data_can_be_list(self):
        msg = tcp_server.make_msg("list_type", [1, 2, 3])
        assert msg["data"] == [1, 2, 3]

    def test_data_can_be_string(self):
        msg = tcp_server.make_msg("text_type", "hello")
        assert msg["data"] == "hello"


# ---------------------------------------------------------------------------
# get_local_ip
# ---------------------------------------------------------------------------

class TestGetLocalIp:
    def test_returns_string(self):
        ip = tcp_server.get_local_ip()
        assert isinstance(ip, str)

    @patch("tcp_server.socket.socket")
    def test_fallback_on_os_error(self, mock_socket_cls):
        mock_sock = MagicMock()
        mock_sock.connect.side_effect = OSError("unreachable")
        mock_socket_cls.return_value = mock_sock
        with patch("tcp_server.socket.gethostbyname", return_value="127.0.0.1"):
            ip = tcp_server.get_local_ip()
        assert isinstance(ip, str)


# ---------------------------------------------------------------------------
# get_weather (caching behaviour)
# ---------------------------------------------------------------------------

class TestGetWeather:
    @patch("tcp_server.fetch_weather", return_value={"temperature": 25.0})
    def test_returns_weather_and_caches(self, mock_fetch):
        result = tcp_server.get_weather()
        assert result["temperature"] == 25.0
        assert tcp_server.last_weather["temperature"] == 25.0

    @patch("tcp_server.fetch_weather", return_value=None)
    def test_returns_cache_when_api_fails(self, mock_fetch):
        tcp_server.last_weather = {"temperature": 20.0}
        result = tcp_server.get_weather()
        assert result["temperature"] == 20.0

    @patch("tcp_server.fetch_weather", return_value=None)
    def test_returns_empty_dict_with_no_cache(self, mock_fetch):
        result = tcp_server.get_weather()
        assert result == {}


# ---------------------------------------------------------------------------
# handle_message
# ---------------------------------------------------------------------------

class TestHandleMessagePing:
    @pytest.mark.asyncio
    async def test_ping_sends_pong(self):
        writer = _make_writer()
        msg = {"type": "ping", "device_id": "dev1", "data": {}}
        await tcp_server.handle_message(msg, writer)
        writer.write.assert_called_once()
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "pong"
        assert "patient_count" in sent["data"]
        assert "connected_devices" in sent["data"]


class TestHandleMessagePatient:
    @pytest.mark.asyncio
    async def test_patient_added_to_queue(self):
        writer = _make_writer()
        patient_data = {"id": "P1", "breathing_rate": 18}
        msg = {"type": "patient", "device_id": "dev1", "data": patient_data}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        assert len(tcp_server.patient_queue) == 1
        assert tcp_server.patient_queue[0]["id"] == "P1"

    @pytest.mark.asyncio
    async def test_patient_sends_ack(self):
        writer = _make_writer()
        msg = {"type": "patient", "device_id": "dev1", "data": {"id": "P1"}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        writer.write.assert_called_once()
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "ack"
        assert sent["data"]["received"] == "patient"


class TestHandleMessageLocation:
    @pytest.mark.asyncio
    async def test_location_stored(self):
        writer = _make_writer()
        msg = {
            "type": "location",
            "device_id": "dev2",
            "data": {"lat": 25.0, "lon": 121.5, "accuracy": 10.0, "role": "rescuer", "name": "Bob"},
        }
        await tcp_server.handle_message(msg, writer)
        assert "dev2" in tcp_server.device_locations
        loc = tcp_server.device_locations["dev2"]
        assert loc["lat"] == 25.0
        assert loc["lon"] == 121.5
        assert loc["role"] == "rescuer"

    @pytest.mark.asyncio
    async def test_location_sends_ack(self):
        writer = _make_writer()
        msg = {"type": "location", "device_id": "dev2", "data": {"lat": 0, "lon": 0}}
        await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "ack"
        assert sent["data"]["received"] == "location"


class TestHandleMessageVoiceResult:
    @pytest.mark.asyncio
    async def test_voice_text_stored(self):
        writer = _make_writer()
        msg = {"type": "voice_result", "device_id": "dev3", "data": {"text": "there are 5 victims"}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        assert tcp_server.current_voice == "there are 5 victims"

    @pytest.mark.asyncio
    async def test_voice_result_sends_ack(self):
        writer = _make_writer()
        msg = {"type": "voice_result", "device_id": "dev3", "data": {"text": "test"}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "ack"


class TestHandleMessageVoiceBroadcast:
    @pytest.mark.asyncio
    async def test_voice_broadcast_is_rebroadcast(self):
        writer = _make_writer()
        msg = {
            "type": "voice_broadcast",
            "device_id": "dev4",
            "data": {"action": "start", "sender_name": "Alice"},
        }
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_broadcast:
            await tcp_server.handle_message(msg, writer)
        mock_broadcast.assert_awaited_once()
        broadcast_msg = mock_broadcast.call_args[0][0]
        assert broadcast_msg["type"] == "voice_broadcast_rx"
        assert broadcast_msg["data"]["sender_name"] == "Alice"
        assert broadcast_msg["data"]["action"] == "start"


class TestHandleMessageReportSummary:
    @pytest.mark.asyncio
    async def test_report_summary_is_broadcast(self):
        writer = _make_writer()
        msg = {
            "type": "report_summary",
            "device_id": "http-server",
            "data": {"report_id": "RPT-20240101-001", "transcription": "hello"},
        }
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_broadcast:
            await tcp_server.handle_message(msg, writer)
        mock_broadcast.assert_awaited_once()
        sent = mock_broadcast.call_args[0][0]
        assert sent["type"] == "report_summary"
        assert sent["data"]["report_id"] == "RPT-20240101-001"


class TestHandleMessageUnknown:
    @pytest.mark.asyncio
    async def test_unknown_type_sends_error(self):
        writer = _make_writer()
        msg = {"type": "completely_unknown", "device_id": "dev5", "data": {}}
        await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "error"
        assert "JSON_PARSE_ERROR" in sent["data"]["code"]


class TestHandleMessageRequestDecision:
    @pytest.mark.asyncio
    async def test_request_decision_sends_ack(self):
        writer = _make_writer()
        msg = {"type": "request_decision", "device_id": "HQ", "data": {"voice_text": "目前有3名紅色傷患"}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "ack"
        assert sent["data"]["received"] == "request_decision"

    @pytest.mark.asyncio
    async def test_request_decision_updates_voice(self):
        writer = _make_writer()
        msg = {"type": "request_decision", "device_id": "HQ", "data": {"voice_text": "需要增援"}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        assert tcp_server.current_voice == "需要增援"

    @pytest.mark.asyncio
    async def test_request_decision_keeps_voice_when_empty(self):
        tcp_server.current_voice = "existing context"
        writer = _make_writer()
        msg = {"type": "request_decision", "device_id": "HQ", "data": {}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        assert tcp_server.current_voice == "existing context"

    @pytest.mark.asyncio
    async def test_request_decision_calls_generate(self):
        writer = _make_writer()
        msg = {"type": "request_decision", "device_id": "HQ", "data": {"voice_text": "test"}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()) as mock_gen:
            await tcp_server.handle_message(msg, writer)
        mock_gen.assert_awaited_once_with("hq_request", writer)

    @pytest.mark.asyncio
    async def test_request_decision_registers_client(self):
        writer = _make_writer()
        msg = {"type": "request_decision", "device_id": "HQ", "data": {}}
        with patch("tcp_server.generate_and_broadcast", new=AsyncMock()):
            await tcp_server.handle_message(msg, writer)
        assert "HQ" in tcp_server.connected_clients


# ---------------------------------------------------------------------------
# broadcast
# ---------------------------------------------------------------------------

class TestBroadcast:
    @pytest.mark.asyncio
    async def test_sends_to_all_clients(self):
        writers = [_make_writer() for _ in range(3)]
        for i, w in enumerate(writers):
            tcp_server.connected_clients[f"dev{i}"] = w

        msg = tcp_server.make_msg("test", {"x": 1})
        await tcp_server.broadcast(msg)

        for w in writers:
            w.write.assert_called_once()

    @pytest.mark.asyncio
    async def test_removes_disconnected_clients(self):
        good_writer = _make_writer()
        bad_writer = _make_writer()
        bad_writer.drain = AsyncMock(side_effect=ConnectionResetError())

        tcp_server.connected_clients["good"] = good_writer
        tcp_server.connected_clients["bad"] = bad_writer

        await tcp_server.broadcast(tcp_server.make_msg("test", {}))

        assert "bad" not in tcp_server.connected_clients
        assert "good" in tcp_server.connected_clients


# ---------------------------------------------------------------------------
# send_to
# ---------------------------------------------------------------------------

class TestSendTo:
    @pytest.mark.asyncio
    async def test_sends_json_newline(self):
        writer = _make_writer()
        msg = tcp_server.make_msg("hello", {"key": "val"})
        await tcp_server.send_to(writer, msg)
        written = writer.write.call_args[0][0]
        assert written.endswith(b"\n")
        decoded = json.loads(written.rstrip(b"\n"))
        assert decoded["type"] == "hello"


# ---------------------------------------------------------------------------
# text_broadcast
# ---------------------------------------------------------------------------

class TestTextBroadcast:
    @pytest.mark.asyncio
    async def test_text_broadcast_sends_rx_and_ack(self):
        writer = _make_writer()
        tcp_server.connected_clients["cmd1"] = writer
        msg = {
            "type": "text_broadcast",
            "device_id": "cmd1",
            "data": {
                "message": "全員撤退！",
                "sender_name": "指揮官",
                "priority": "urgent",
            },
        }
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_bc:
            await tcp_server.handle_message(msg, writer)
            # broadcast was called with text_broadcast_rx
            bc_msg = mock_bc.call_args[0][0]
            assert bc_msg["type"] == "text_broadcast_rx"
            assert bc_msg["data"]["message"] == "全員撤退！"
            assert bc_msg["data"]["priority"] == "urgent"
            assert bc_msg["data"]["broadcast_id"].startswith("MSG-")
        # ACK was sent to writer
        ack = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert ack["type"] == "ack"
        assert ack["data"]["received"] == "text_broadcast"

    def test_next_broadcast_id_increments(self):
        id1 = tcp_server._next_broadcast_id()
        id2 = tcp_server._next_broadcast_id()
        assert id1.startswith("MSG-")
        assert id1 != id2


# ---------------------------------------------------------------------------
# message_ack (read receipts)
# ---------------------------------------------------------------------------

class TestMessageAck:
    @pytest.mark.asyncio
    async def test_ack_updates_tracker_and_broadcasts(self):
        writer = _make_writer()
        # Register a message to track
        tcp_server.connected_clients["dev1"] = writer
        tcp_server.connected_clients["dev2"] = _make_writer()
        await tcp_server._register_read_tracker("DEC-001")

        msg = {
            "type": "message_ack",
            "device_id": "dev1",
            "data": {"message_id": "DEC-001", "message_type": "decision"},
        }
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_bc:
            await tcp_server.handle_message(msg, writer)
            bc_msg = mock_bc.call_args[0][0]
            assert bc_msg["type"] == "read_status"
            assert bc_msg["data"]["read_count"] == 1

    @pytest.mark.asyncio
    async def test_register_read_tracker(self):
        tcp_server.connected_clients["a"] = _make_writer()
        tcp_server.connected_clients["b"] = _make_writer()
        await tcp_server._register_read_tracker("TEST-001")
        assert tcp_server.message_read_tracker["TEST-001"]["total"] == 2
        assert len(tcp_server.message_read_tracker["TEST-001"]["read"]) == 0

    @pytest.mark.asyncio
    async def test_get_read_status(self):
        tcp_server.connected_clients["a"] = _make_writer()
        tcp_server.connected_clients["b"] = _make_writer()
        tcp_server.message_read_tracker["TEST-002"] = {"total": 2, "read": {"a"}}
        status = await tcp_server._get_read_status("TEST-002")
        assert status["read_count"] == 1
        assert status["total"] == 2
        assert "b" in status["unread_devices"]

    @pytest.mark.asyncio
    async def test_ack_unknown_message(self):
        writer = _make_writer()
        msg = {
            "type": "message_ack",
            "device_id": "dev1",
            "data": {"message_id": "UNKNOWN-999", "message_type": "decision"},
        }
        await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "ack"
        assert sent["data"]["status"] == "unknown_message"


# ---------------------------------------------------------------------------
# translate_request
# ---------------------------------------------------------------------------

class TestTranslateRequest:
    @pytest.mark.asyncio
    async def test_translate_sends_ack_immediately(self):
        writer = _make_writer()
        msg = {
            "type": "translate_request",
            "device_id": "dev1",
            "data": {"text": "你好", "source_lang": "zh-TW", "target_lang": "en"},
        }
        await tcp_server.handle_message(msg, writer)
        sent = json.loads(writer.write.call_args[0][0].rstrip(b"\n"))
        assert sent["type"] == "ack"
        assert sent["data"]["received"] == "translate_request"


# ---------------------------------------------------------------------------
# patient_warning
# ---------------------------------------------------------------------------

class TestPatientWarning:
    @pytest.mark.asyncio
    async def test_patient_warning_broadcasts(self):
        writer = _make_writer()
        msg = {
            "type": "patient_warning",
            "device_id": "monitor",
            "data": {
                "patient_id": "P001",
                "priority": "紅色",
                "location": "1F大廳",
                "minutes_since_triage": 18,
                "warning_level": "high",
                "message": "紅色傷患P001已等待18分鐘",
            },
        }
        with patch("tcp_server.broadcast", new=AsyncMock()) as mock_bc:
            await tcp_server.handle_message(msg, writer)
            bc_msg = mock_bc.call_args[0][0]
            assert bc_msg["type"] == "patient_warning"
            assert bc_msg["data"]["patient_id"] == "P001"
            assert bc_msg["data"]["warning_level"] == "high"
