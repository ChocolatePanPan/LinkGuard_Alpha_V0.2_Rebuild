from __future__ import annotations

import asyncio
import os
import struct
import time
import io
import wave
from datetime import datetime, timezone, timedelta

import httpx
from utils import now_iso
import os
from usb_backup import sync_radio, RADIO_DIR

UDP_PORT = 9001
RELAY_PORT = 9002   # 中繼音訊發送到客戶端的接收 port（與 iOS/Mac 監聽 port 一致）
_WHISPER_HOST = os.environ.get("WHISPER_HOST", "localhost")
WHISPER_URL = f"http://{_WHISPER_HOST}:8002/transcribe"
MAGIC = 0x4C474244  # "LGBD"
SILENCE_TIMEOUT = 2.0  # 秒，無封包即視為廣播結束
SAMPLE_RATE = 16000
TZ_TW = timezone(timedelta(hours=8))

# === 全域狀態 ===
udp_clients: dict[str, tuple] = {}      # {device_id: (ip, port)}
audio_buffer: dict[str, list[bytes]] = {}  # {device_id: [PCM chunks]}
last_packet: dict[str, float] = {}       # {device_id: monotonic timestamp}
_seq_sets: dict[str, set] = {}           # {device_id: set(sequence)} 防重複



def parse_header(data: bytes) -> tuple[str, int, int, bytes] | None:
    """解析 UDP 封包標頭，回傳 (device_id, sequence, timestamp_ms, audio_data) 或 None"""
    if len(data) < 18:
        return None
    magic = struct.unpack("!I", data[0:4])[0]
    if magic != MAGIC:
        return None
    dev_len = struct.unpack("!H", data[4:6])[0]
    if len(data) < 6 + dev_len + 12:
        return None
    device_id = data[6:6 + dev_len].decode("utf-8", errors="replace")
    offset = 6 + dev_len
    sequence = struct.unpack("!I", data[offset:offset + 4])[0]
    timestamp_ms = struct.unpack("!Q", data[offset + 4:offset + 12])[0]
    audio_data = data[offset + 12:]
    return device_id, sequence, timestamp_ms, audio_data


def pcm_to_wav(pcm_chunks: list[bytes]) -> bytes:
    """PCM 16bit 16kHz mono → WAV bytes"""
    pcm = b"".join(pcm_chunks)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm)
    return buf.getvalue()


async def send_to_whisper(device_id: str, pcm_chunks: list[bytes]):
    """將累積的 PCM 音訊存回 RADIO_DIR 作備份，同時送給 whisper_server 轉錄"""
    if not pcm_chunks:
        return
    wav_data = pcm_to_wav(pcm_chunks)
    
    # 電臺備份 (Radio Backup) 最新的算法
    radio_id = f"{device_id}_{datetime.now(TZ_TW).strftime('%Y%m%d_%H%M%S')}"
    file_path = os.path.join(RADIO_DIR, f"{radio_id}.wav")
    try:
        os.makedirs(RADIO_DIR, exist_ok=True)
        with open(file_path, "wb") as f:
            f.write(wav_data)
        print(f"[UDP] 廣播音訊已備份: {file_path}")
        
        # 呼叫 usb_backup
        await asyncio.to_thread(sync_radio, radio_id)
    except Exception as e:
        print(f"[UDP] 備份廣播音訊失敗: {e}")

    try:
        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(
                WHISPER_URL,
                files={"file": ("broadcast.wav", wav_data, "audio/wav")},
                data={"source": "broadcast", "sender_id": device_id},
            )
            if resp.status_code == 200:
                text = resp.json().get("text", "")
                print(f"[UDP] Whisper 轉錄完成 ({device_id}): {text[:60]}")
            else:
                print(f"[UDP] Whisper 回應 {resp.status_code}")
    except Exception as e:
        print(f"[UDP] 送 Whisper 失敗: {e}")


async def check_timeouts():
    """定期檢查是否有廣播已結束（超過 SILENCE_TIMEOUT 無封包）"""
    while True:
        await asyncio.sleep(0.5)
        now = time.monotonic()
        finished = []
        for dev_id, ts in last_packet.items():
            if now - ts > SILENCE_TIMEOUT and dev_id in audio_buffer:
                finished.append(dev_id)
        for dev_id in finished:
            chunks = audio_buffer.pop(dev_id, [])
            last_packet.pop(dev_id, None)
            _seq_sets.pop(dev_id, None)
            if chunks:
                print(f"[UDP] 廣播結束 {dev_id}, 累積 {len(chunks)} 個封包, 送 Whisper")
                asyncio.create_task(send_to_whisper(dev_id, chunks))


class BroadcastProtocol(asyncio.DatagramProtocol):
    def __init__(self):
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data: bytes, addr: tuple):
        parsed = parse_header(data)
        if parsed is None:
            return

        device_id, sequence, timestamp_ms, audio_data = parsed

        # 註冊客戶端（只記 IP，中繼時一律發到 RELAY_PORT）
        client_ip = addr[0]
        udp_clients[device_id] = client_ip

        # 心跳封包（音訊 ≤ 2 bytes）僅用於註冊，不轉發也不累積
        if len(audio_data) <= 2:
            return

        # 防重複
        if device_id not in audio_buffer:
            audio_buffer[device_id] = []
            _seq_sets[device_id] = set()
            print(f"[UDP] 新廣播開始: {device_id}")

        if sequence in _seq_sets.get(device_id, set()):
            return  # 重複封包
        _seq_sets[device_id].add(sequence)
        audio_buffer[device_id].append(audio_data)
        last_packet[device_id] = time.monotonic()

        # 轉送音訊給所有其他 UDP 客戶端（發到 RELAY_PORT）
        for client_id, client_ip in udp_clients.items():
            if client_id != device_id:
                try:
                    self.transport.sendto(data, (client_ip, RELAY_PORT))
                except Exception:
                    pass


async def main():
    print(f"[UDP] 語音廣播伺服器啟動於 0.0.0.0:{UDP_PORT}")

    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(
        BroadcastProtocol,
        local_addr=("0.0.0.0", UDP_PORT),
    )

    # 啟動超時檢查
    asyncio.create_task(check_timeouts())

    try:
        await asyncio.Future()  # run forever
    finally:
        transport.close()


if __name__ == "__main__":
    asyncio.run(main())
