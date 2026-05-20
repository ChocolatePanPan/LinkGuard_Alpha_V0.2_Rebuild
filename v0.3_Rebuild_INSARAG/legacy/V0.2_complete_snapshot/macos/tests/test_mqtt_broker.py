"""
Tests for mqtt_broker.py – MQTT message parsing, node status, and LLM formatter.
paho.mqtt.client is mocked via sys.modules so no real MQTT broker is needed.
"""
import sys
import os
import json
import pytest
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Stub out paho.mqtt before importing mqtt_broker
# ---------------------------------------------------------------------------
paho_stub = MagicMock()
paho_stub.mqtt.client.CallbackAPIVersion.VERSION2 = 2
sys.modules.setdefault("paho", paho_stub)
sys.modules.setdefault("paho.mqtt", paho_stub.mqtt)
sys.modules.setdefault("paho.mqtt.client", paho_stub.mqtt.client)

# Stub linkguard_db to avoid real DB operations
linkguard_db_stub = MagicMock()
sys.modules.setdefault("linkguard_db", linkguard_db_stub)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mqtt_broker


@pytest.fixture(autouse=True)
def clear_node_status():
    """Reset the global node_status dict before every test."""
    mqtt_broker.node_status.clear()
    yield
    mqtt_broker.node_status.clear()


def _make_mqtt_msg(payload: dict) -> MagicMock:
    """Create a mock paho mqtt.MQTTMessage with the given payload."""
    msg = MagicMock()
    msg.payload = json.dumps(payload).encode()
    return msg


# ---------------------------------------------------------------------------
# on_message – valid payloads
# ---------------------------------------------------------------------------

class TestOnMessage:

    def test_valid_message_updates_node_status(self):
        payload = {
            "node_id": "N1",
            "rssi": -70,
            "snr": 5.2,
            "battery": 87.5,
            "location": {"lat": 25.0, "lon": 121.5},
            "pdr": 98,
            "timestamp": "2024-01-01T10:00:00",
        }
        mqtt_broker.on_message(None, None, _make_mqtt_msg(payload))
        assert "N1" in mqtt_broker.node_status
        status = mqtt_broker.node_status["N1"]
        assert status["rssi"] == -70
        assert status["snr"] == 5.2
        assert status["battery"] == 87.5
        assert status["pdr"] == 98
        assert status["online"] is True
        assert status["timestamp"] == "2024-01-01T10:00:00"

    def test_multiple_nodes_stored_independently(self):
        for i in range(3):
            mqtt_broker.on_message(
                None, None,
                _make_mqtt_msg({"node_id": f"N{i}", "rssi": -60 - i})
            )
        assert len(mqtt_broker.node_status) == 3
        for i in range(3):
            assert f"N{i}" in mqtt_broker.node_status

    def test_repeated_message_overwrites_node(self):
        mqtt_broker.on_message(None, None, _make_mqtt_msg({"node_id": "N1", "battery": 50.0}))
        mqtt_broker.on_message(None, None, _make_mqtt_msg({"node_id": "N1", "battery": 20.0}))
        assert mqtt_broker.node_status["N1"]["battery"] == 20.0

    def test_missing_node_id_uses_unknown(self):
        mqtt_broker.on_message(None, None, _make_mqtt_msg({"rssi": -80}))
        assert "unknown" in mqtt_broker.node_status

    def test_missing_optional_fields_default_to_zero(self):
        mqtt_broker.on_message(None, None, _make_mqtt_msg({"node_id": "N2"}))
        status = mqtt_broker.node_status["N2"]
        assert status["rssi"] == 0
        assert status["snr"] == 0
        assert status["battery"] == 0.0
        assert status["pdr"] == 0
        assert status["location"] == {}
        assert status["last_seen"] == ""

    def test_location_dict_is_preserved(self):
        payload = {
            "node_id": "N3",
            "location": {"lat": 24.1, "lon": 120.7},
        }
        mqtt_broker.on_message(None, None, _make_mqtt_msg(payload))
        loc = mqtt_broker.node_status["N3"]["location"]
        assert loc["lat"] == 24.1
        assert loc["lon"] == 120.7


# ---------------------------------------------------------------------------
# on_message – invalid payloads
# ---------------------------------------------------------------------------

class TestOnMessageInvalid:

    def test_invalid_json_does_not_raise(self):
        msg = MagicMock()
        msg.payload = b"not valid json {"
        # Should catch the exception internally and not propagate
        mqtt_broker.on_message(None, None, msg)
        assert len(mqtt_broker.node_status) == 0

    def test_empty_payload_does_not_raise(self):
        msg = MagicMock()
        msg.payload = b""
        mqtt_broker.on_message(None, None, msg)
        assert len(mqtt_broker.node_status) == 0


# ---------------------------------------------------------------------------
# get_node_status
# ---------------------------------------------------------------------------

class TestGetNodeStatus:

    def test_returns_empty_dict_initially(self):
        result = mqtt_broker.get_node_status()
        assert result == {}

    def test_returns_copy_not_reference(self):
        mqtt_broker.on_message(None, None, _make_mqtt_msg({"node_id": "X"}))
        result = mqtt_broker.get_node_status()
        result["mutated"] = True
        assert "mutated" not in mqtt_broker.node_status

    def test_returns_all_stored_nodes(self):
        for nid in ["A", "B", "C"]:
            mqtt_broker.on_message(None, None, _make_mqtt_msg({"node_id": nid}))
        result = mqtt_broker.get_node_status()
        assert set(result.keys()) == {"A", "B", "C"}


# ---------------------------------------------------------------------------
# format_nodes_for_llm
# ---------------------------------------------------------------------------

class TestFormatNodesForLLM:

    def test_empty_nodes_returns_empty_string(self):
        assert mqtt_broker.format_nodes_for_llm() == ""

    def test_single_node_format(self):
        mqtt_broker.on_message(
            None, None,
            _make_mqtt_msg({
                "node_id": "N1",
                "battery": 90.0,
                "rssi": -65,
                "location": {"lat": 25.0, "lon": 121.5},
            }),
        )
        out = mqtt_broker.format_nodes_for_llm()
        assert "N1" in out
        assert "90.0" in out
        assert "-65" in out

    def test_multiple_nodes_produce_multiple_lines(self):
        for i in range(3):
            mqtt_broker.on_message(
                None, None,
                _make_mqtt_msg({"node_id": f"N{i}"}),
            )
        lines = mqtt_broker.format_nodes_for_llm().strip().split("\n")
        assert len(lines) == 3

    def test_output_contains_location_coordinates(self):
        mqtt_broker.on_message(
            None, None,
            _make_mqtt_msg({
                "node_id": "NX",
                "battery": 50.0,
                "rssi": -80,
                "location": {"lat": 23.5, "lon": 120.3},
            }),
        )
        out = mqtt_broker.format_nodes_for_llm()
        assert "23.5" in out
        assert "120.3" in out
