# LinkGuard macOS Backend

Native macOS port of the [win11/](../win11) Python backend. Same 9 services
(MQTT / TCP / UDP / HTTP / Photo / Stats / Resource / Gemma4 AI / Whisper)
on the same ports — just running on macOS instead of Windows.

The iOS / Android field apps and the SwiftUI `LinkGuardHQ` app need **no
changes**: they discover this backend via Bonjour (`_linkguard._tcp.local.`)
exactly as they did with the Windows backend.

---

## 1. Prerequisites

```bash
brew install python@3.11 ollama ffmpeg
```

| Tool       | Why                                                        |
|------------|------------------------------------------------------------|
| `python@3.11` | Runs all backend services                              |
| `ollama`   | Local Gemma4 LLM inference (Metal-accelerated on Apple Silicon) |
| `ffmpeg`   | Required by `av` (PyAV) for audio decoding in Whisper      |

Recommended hardware:
- Apple Silicon (M1/M2/M3) with **≥ 16 GB** unified memory for `gemma4:e4b`.
- **≥ 32 GB** unified memory if you intend to run `gemma4:26b` locally.

---

## 2. Set up Python environment

From the repo root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r macos/requirements.txt
```

If `onnxruntime` fails to install on Apple Silicon, swap it for
`onnxruntime-silicon`:

```bash
pip uninstall onnxruntime
pip install onnxruntime-silicon
```

Smoke-test the imports:

```bash
python3 -c "import faster_whisper, av, onnxruntime, paho.mqtt, zeroconf, fastapi, ollama; print('ok')"
```

---

## 3. Set up Ollama models

```bash
ollama serve &        # starts http://localhost:11434 (Metal-accelerated)
ollama pull gemma4:e2b
ollama pull gemma4:e4b
# Optional, only if you have ≥ 32 GB RAM:
ollama pull gemma4:26b

# Recreate the LinkGuard custom model:
ollama create gemma4-linkguard2.0 -f macos/Modelfile.gemma4
ollama list
```

---

## 4. Run the backend

```bash
chmod +x macos/start_all.sh macos/stop_all.sh macos/start_hq.sh
cd macos
./start_all.sh         # interactive: pick standalone / small / large
```

`start_all.sh` writes per-service PIDs to `logs/*.pid` and per-service stdout
to `logs/*.log`. Tail any one with:

```bash
tail -f logs/gemma4_server.log
```

To stop everything:

```bash
./stop_all.sh
```

To run the (optional) Python HQ server instead of the native SwiftUI HQ app:

```bash
./start_hq.sh
# Open http://localhost:8080
```

---

## 5. Verify it works

```bash
# Service health
curl http://localhost:8001/health   # gemma4_server
curl http://localhost:8002/health   # whisper_server
curl http://localhost:8003/health   # http_server
nc -zv localhost 9000               # tcp_server
nc -zv localhost 1883               # MQTT

# Bonjour publication (run for 3-5 s, then Ctrl-C)
dns-sd -B _linkguard._tcp

# End-to-end Ollama
curl -X POST http://localhost:11434/api/generate \
     -d '{"model":"gemma4-linkguard2.0","prompt":"ping","stream":false}'
```

Then launch the iOS field app on the same Wi-Fi network — it should
auto-discover this Mac via Bonjour and start sending traffic. New rows
should appear in `data/linkguard.db`.

---

## 6. What changed vs. the Windows version?

| Area | Win11 | macOS |
|------|-------|-------|
| Launch script | `start_all.bat` (`netstat` + `taskkill`) | `start_all.sh` (`lsof` + `kill -9`) |
| Stop script   | `stop_all.bat` (`taskkill /IM python.exe`) | `stop_all.sh` (PID-file based) |
| Whisper backend | `device="cuda"`, `compute_type="float16"` | `device="cpu"`, `compute_type="int8"` (Darwin auto-detect in [whisper_server.py](whisper_server.py)) |
| LLM runtime   | Ollama on CUDA | Ollama on Metal (automatic) |
| USB scan      | drive letters `D:\…H:\` | `/Volumes/*` (already supported in [usb_backup.py](usb_backup.py)) |
| Everything else | — | unchanged |

Override Whisper choice via environment variables if needed:

```bash
WHISPER_MODEL=medium WHISPER_DEVICE=cpu WHISPER_COMPUTE_TYPE=int8 ./start_all.sh
```

---

## 7. Known limitations

1. **Whisper performance** — `large-v3 + int8` on CPU is roughly 2–3× slower
   than the CUDA `float16` path on Windows. If unacceptable, try
   `WHISPER_MODEL=medium` or evaluate `whisper.cpp` (Metal-accelerated) as a
   drop-in replacement.
2. **macOS firewall** — On first launch each service triggers an
   "Allow incoming connections?" prompt. Approve them, or pre-approve via:
   ```bash
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
        --add /usr/local/bin/python3 \
        --unblock /usr/local/bin/python3
   ```
3. **Ollama model size** — `gemma4:26b` is ~15 GB; only pull on the host
   that will actually serve as the "large" tier in dual-model mode.
