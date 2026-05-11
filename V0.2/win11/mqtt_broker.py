from __future__ import annotations

import json
import paho.mqtt.client as mqtt

MQTT_HOST = "localhost"
MQTT_PORT = 1883
SUBSCRIBE_TOPIC = "linkguard/nodes/#"

# 全域節點狀態字典
node_status: dict[str, dict] = {}


def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code == 0:
        print(f"[MQTT] 已連線到 {MQTT_HOST}:{MQTT_PORT}")
        client.subscribe(SUBSCRIBE_TOPIC)
        print(f"[MQTT] 已訂閱 {SUBSCRIBE_TOPIC}")
    else:
        print(f"[MQTT] 連線失敗, reason_code={reason_code}")


def on_disconnect(client, userdata, flags, reason_code, properties=None):
    if reason_code != 0:
        print(f"[MQTT] 意外斷線 reason_code={reason_code}, 自動重連中...")


def on_message(client, userdata, msg):
    """解析MQTT訊息並更新節點狀態字典"""
    try:
        payload = json.loads(msg.payload.decode())
        node_id = payload.get("node_id", "unknown")
        node_status[node_id] = {
            "node_id": node_id,
            "rssi": payload.get("rssi", 0),
            "snr": payload.get("snr", 0),
            "battery": payload.get("battery", 0.0),
            "location": payload.get("location", {}),
            "pdr": payload.get("pdr", 0),
            "online": True,
            "last_seen": payload.get("timestamp", ""),
            "timestamp": payload.get("timestamp", ""),
        }
        print(
            f"[MQTT] 更新節點 {node_id}: "
            f"RSSI={payload.get('rssi')}, SNR={payload.get('snr')}, "
            f"電量={payload.get('battery')}%, PDR={payload.get('pdr')}%"
        )
    except (json.JSONDecodeError, Exception) as e:
        print(f"[MQTT] 訊息解析失敗: {e}")


def get_node_status() -> dict:
    """回傳所有節點目前狀態"""
    return dict(node_status)


def format_nodes_for_llm() -> str:
    """格式化節點狀態給LLM

    格式: [節點X] 電量:X% | RSSI:X | 位置:X,X
    """
    lines = []
    for nid, info in node_status.items():
        loc = info.get("location", {})
        lat = loc.get("lat", 0)
        lon = loc.get("lon", 0)
        lines.append(
            f"[節點{nid}] 電量:{info.get('battery', 0)}% | "
            f"RSSI:{info.get('rssi', 0)} | "
            f"位置:{lat},{lon}"
        )
    return "\n".join(lines)


if __name__ == "__main__":
    import time

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    # 斷線自動重連：設定重連延遲（1~30秒指數退避）
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    while True:
        try:
            print(f"[MQTT] 連線到 {MQTT_HOST}:{MQTT_PORT}...")
            client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
            client.loop_forever()
        except ConnectionRefusedError:
            print("[MQTT] Broker 無回應，5秒後重試...")
            time.sleep(5)
        except KeyboardInterrupt:
            print("\n[MQTT] 停止監聽")
            client.disconnect()
            break
