import asyncio
import io
import json
import os
import socket
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from faster_whisper import WhisperModel
from utils import now_iso, api_ok, health_check_response
from i18n import t

TZ_TW = timezone(timedelta(hours=8))
TCP_SERVER_HOST = os.environ.get("TCP_SERVER_HOST", "127.0.0.1")
TCP_SERVER_PORT = 9000

# === FastAPI App ===
app = FastAPI(title="LinkGuard Whisper Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

model: WhisperModel | None = None



@app.on_event("startup")
def startup():
    global model
    print("[Whisper] 載入 large-v3 模型 (CUDA float16)...")
    model = WhisperModel("large-v3", device="cuda", compute_type="float16")
    print("[Whisper] 模型載入完成")


def _send_to_tcp_sync(text: str, language: str, duration: float,
                       source: str, sender_id: str):
    """將轉錄結果送到 tcp_server（同步版本）"""
    msg = json.dumps({
        "type": "voice_result",
        "device_id": "whisper-server",
        "timestamp": now_iso(),
        "data": {
            "text": text,
            "language": language,
            "duration": duration,
            "source": source,
            "sender_id": sender_id,
        },
    }, ensure_ascii=False) + "\n"
    s = None
    try:
        s = socket.create_connection((TCP_SERVER_HOST, TCP_SERVER_PORT), timeout=5)
        s.sendall(msg.encode())
        resp = s.recv(4096)
        print(f"[Whisper] 已送出至 tcp_server, 回應: {resp.decode().strip()}")
    except Exception as e:
        print(f"[Whisper] 送出至 tcp_server 失敗: {e}")
    finally:
        if s is not None:
            try:
                s.close()
            except Exception:
                pass


async def send_to_tcp_server(text: str, language: str, duration: float,
                       source: str, sender_id: str):
    """將轉錄結果送到 tcp_server（非同步包裝）"""
    await asyncio.to_thread(_send_to_tcp_sync, text, language, duration, source, sender_id)


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    source: str = Form("broadcast"),
    sender_id: str = Form("unknown"),
    language: str = Form("zh"),
):
    if model is None:
        raise HTTPException(status_code=503, detail=t("err.model_not_loaded"))
    audio_bytes = await file.read()
    audio_stream = io.BytesIO(audio_bytes)

    lang_param = language if language != "auto" else None
    segments, info = model.transcribe(audio_stream, language=lang_param)
    text = "".join(seg.text for seg in segments)
    duration = round(info.duration, 2)

    print(f"[Whisper] 轉錄完成 ({source}/{sender_id}, lang={info.language}): {text[:80]}...")

    # 非同步送到 tcp_server
    await send_to_tcp_server(text, info.language, duration, source, sender_id)

    return api_ok({
        "text": text,
        "language": info.language,
        "duration": duration,
    })


@app.get("/health")
def health():
    import torch
    return health_check_response(
        "whisper-server",
        extras={
            "model_loaded": model is not None,
            "cuda_available": torch.cuda.is_available(),
        },
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8002)
