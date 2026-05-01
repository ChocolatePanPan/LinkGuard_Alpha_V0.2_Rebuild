"""Quick script to show actual Qwen responses for integration test prompts."""
import httpx, json

HOST = "http://localhost:11434"
MODEL = "linkguard-qwen"

def call(prompt, label, keywords=None):
    print(f"\n{'='*60}")
    print(f"TEST: {label}")
    print(f"PROMPT: {prompt}")
    print(f"{'='*60}")
    r = httpx.post(f"{HOST}/api/chat", json={
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False, "think": False,
        "options": {"num_predict": 64, "temperature": 0.1},
    }, timeout=120)
    content = r.json()["message"]["content"]
    print(f"RESPONSE: {content}")
    if keywords:
        hits = [w for w in keywords if w in content.lower()]
        print(f"MATCHED: {hits}  ->  {'PASS' if hits else 'FAIL'}")

call("回覆OK", "test_model_responds")
call("你是災害救援指揮AI。現場一名傷患無呼吸，請依 START 檢傷分類標準判定其傷檢等級，只回答顏色和等級名稱。",
     "test_model_triage_prompt", ["黑"])
call("將以下文字翻譯為英文，只輸出翻譯結果：傷患無法呼吸",
     "test_model_translation", ["breath", "patient", "unable"])
