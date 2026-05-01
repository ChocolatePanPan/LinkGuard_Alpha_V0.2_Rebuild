"""
LinkGuard 檢傷評分模組
======================
- START 三步驟初篩分類（黑/紅/綠）
- 六維度加權評分（生命危急、時間壓力、存活可能、傷勢嚴重、環境風險、救援成本）
- Total Score = START加成 + Σ(原始分數 × 權重)
- 救援優先序依 Total Score 降序；同分時 START 紅標優先
"""

# ── 六維度定義 ──────────────────────────────────────────────
# 每個維度有 weight 及其下的評分項目（key → 原始分數）。
# 同維度多項條件若同時符合，依規範範例全部計入（各乘以維度權重後累加）。

DIMENSIONS = {
    "vitals": {                 # 生命危急程度
        "weight": 1.5,
        "label": "生命危急程度",
        "items": {
            "breathing_difficulty": 40,   # 呼吸困難
            "heavy_bleeding":       50,   # 大量出血
            "weak_heartbeat":       30,   # 心跳微弱
            "unconscious":          30,   # 意識不清
        },
    },
    "time_pressure": {          # 時間壓力
        "weight": 1.4,
        "label": "時間壓力",
        "items": {
            "deteriorate_1h": 40,         # 1 小時內惡化
            "deteriorate_3h": 25,         # 3 小時內惡化
            "condition_stable": 5,        # 狀況穩定
        },
    },
    "survival": {               # 存活可能性
        "weight": 1.3,
        "label": "存活可能性",
        "items": {
            "high_survival":     30,      # 高存活率
            "medium_survival":   10,      # 中等存活率
            "very_low_survival": -40,     # 極低存活率
        },
    },
    "injury": {                 # 傷勢嚴重度
        "weight": 1.2,
        "label": "傷勢嚴重度",
        "items": {
            "severe_injury":   40,        # 重傷 — 內出血/壓傷
            "moderate_injury": 20,        # 中等傷 — 骨折
            "minor_injury":     5,        # 輕傷
        },
    },
    "environment": {            # 環境風險
        "weight": 1.1,
        "label": "環境風險",
        "items": {
            "env_fire":         40,       # 火災/瓦斯外洩
            "env_collapse":     30,       # 建築可能倒塌
            "env_inaccessible": -20,      # 位置難以接近
        },
    },
    "rescue_cost": {            # 救援成本
        "weight": 1.0,
        "label": "救援成本",
        "items": {
            "rescue_long_time":       -30,  # 需長時間救援
            "rescue_heavy_manpower":  -20,  # 需大量人力
            "rescue_heavy_equipment": -20,  # 需重型設備
        },
    },
}

# START 標籤排序權重（同分時紅優先）
_PRIORITY_ORDER = {"紅色": 0, "綠色": 1, "黑色": 2}


# ── START 三步驟分類 ────────────────────────────────────────

def triage_START(patient: dict, persist: bool = True) -> dict:
    """START 三步驟初篩分類。

    Args:
        patient: 傷患資料 dict
        persist: 是否儲存到資料庫（當 _recalc_all_patients 呼叫時設為 False，避免覆寫 timestamp）

    回傳 dict 包含:
      priority  — 黑色 / 紅色 / 綠色
      reason    — 分類原因描述
      start_bonus — START 加成分數
    """
    breathing_rate = patient.get("breathing_rate", 0)
    capillary_refill = patient.get("capillary_refill", 0.0)
    can_follow_commands = patient.get("can_follow_commands", True)

    # STEP 1: DECEASED（黑）— 開放氣道後仍無呼吸
    if breathing_rate == -1:
        result = {"priority": "黑色", "reason": "無呼吸", "start_bonus": -200}
    # STEP 2: IMMEDIATE（紅）— 呼吸 > 30/min
    elif breathing_rate > 30:
        result = {"priority": "紅色", "reason": "呼吸大於30次/分", "start_bonus": 60}
    # STEP 2: IMMEDIATE（紅）— 無脈搏或 CRT > 2 秒
    elif capillary_refill > 2 or capillary_refill == -1:
        result = {"priority": "紅色", "reason": "微血管回填>2秒或無橈動脈脈搏", "start_bonus": 60}
    # STEP 3: IMMEDIATE（紅）— 無法遵從簡單指令
    elif not can_follow_commands:
        result = {"priority": "紅色", "reason": "無法遵從指令", "start_bonus": 60}
    # MINOR（綠）— 三項均正常
    else:
        result = {"priority": "綠色", "reason": "三項檢查正常", "start_bonus": 0}

    # 儲存到統一資料庫
    if persist:
        try:
            import linkguard_db
            combined = {**patient, **result}
            linkguard_db.save_patient(combined)
        except Exception:
            pass  # DB 儲存失敗不影響檢傷結果

    return result


# ── 六維度加權評分 ──────────────────────────────────────────

def score_dimensions(patient: dict) -> tuple:
    """計算六維度加權分數。

    回傳 (total_float, details_list)
      total_float — 六維度加權總分
      details_list — 每筆匹配項目的明細 dict
    """
    total = 0.0
    details = []

    for dim_key, dim_cfg in DIMENSIONS.items():
        weight = dim_cfg["weight"]
        for item_key, raw_score in dim_cfg["items"].items():
            if patient.get(item_key):
                weighted = raw_score * weight
                total += weighted
                details.append({
                    "dimension": dim_cfg["label"],
                    "item": item_key,
                    "raw": raw_score,
                    "weight": weight,
                    "weighted": weighted,
                })

    return total, details


# ── 總分計算 ────────────────────────────────────────────────

def calculate_total_score(patient: dict, persist: bool = True) -> dict:
    """完整評分：START 加成 + 六維度加權。

    Args:
        patient: 傷患資料 dict
        persist: 是否儲存到資料庫

    回傳 dict:
      priority, reason, start_bonus,
      dimension_score, total_score, dimensions
    """
    start_result = triage_START(patient, persist=persist)
    start_bonus = start_result["start_bonus"]

    dim_score, dim_details = score_dimensions(patient)
    total = start_bonus + dim_score

    return {
        "priority": start_result["priority"],
        "reason": start_result["reason"],
        "start_bonus": start_bonus,
        "dimension_score": round(dim_score, 1),
        "total_score": round(total, 1),
        "dimensions": dim_details,
    }


# ── 救援優先序排列 ──────────────────────────────────────────

def rank_patients(patients: list) -> list:
    """對所有傷患評分並依 total_score 降序排列。

    同分時 START 紅標優先。
    黑色（DECEASED）排在最末。
    """
    scored = []
    for p in patients:
        result = calculate_total_score(p)
        scored.append({**p, **result})

    scored.sort(
        key=lambda x: (-x["total_score"], _PRIORITY_ORDER.get(x["priority"], 9))
    )

    # 加上排序序號
    for idx, item in enumerate(scored, 1):
        item["rank"] = idx

    return scored


# ── LLM prompt 格式化 ──────────────────────────────────────

def format_for_llm(patients: list) -> str:
    """將傷員清單格式化為 LLM prompt 字串。

    輸出完整關鍵欄位（姓名、年齡、生命徵象原始數值、GPS、備註等），
    讓 AI 能基於完整資訊做判斷，而非只看到評分結果。
    若傷員已含 total_score 則輸出分數與排名。
    """
    lines = []
    for i, p in enumerate(patients, 1):
        patient_id = p.get("id", f"傷員{i}")
        location = p.get("location", "未知區")
        priority = p.get("priority", "未知")
        reason = p.get("reason", "無")

        # 標題列：ID / 姓名 / 年齡
        name = (p.get("name") or "").strip()
        age = p.get("age")
        ident_parts = [f"[{patient_id}]"]
        if name:
            ident_parts.append(f"姓名：{name}")
        if isinstance(age, (int, float)) and age:
            ident_parts.append(f"年齡：{int(age)}")
        header = " ".join(ident_parts)

        # 分類列：優先級 / 原因 / 位置
        triage_line = f"  · 優先級：{priority} | 原因：{reason} | 位置：{location}"
        if "total_score" in p:
            score = p["total_score"]
            rank = p.get("rank", "?")
            triage_line += f" | 分數：{score} | 排序：#{rank}"

        # 生命徵象列：呼吸 / 微血管回填 / 意識
        br = p.get("breathing_rate")
        cr = p.get("capillary_refill")
        cfc = p.get("can_follow_commands")
        vital_parts = []
        if br is not None:
            vital_parts.append("呼吸：無" if br == -1 else f"呼吸：{br}/min")
        if cr is not None:
            vital_parts.append("微血管：無脈搏" if cr == -1 else f"微血管回填：{cr}s")
        if cfc is not None:
            vital_parts.append("意識：可聽令" if cfc else "意識：無法聽令")
        vital_line = "  · 生命徵象：" + " | ".join(vital_parts) if vital_parts else ""

        # GPS 列（若提供）
        gps = p.get("gps") or {}
        gps_line = ""
        if isinstance(gps, dict):
            lat, lon = gps.get("lat"), gps.get("lon")
            if lat is not None and lon is not None:
                gps_line = f"  · GPS：{lat:.5f}, {lon:.5f}"

        # 備註列（搜救人員第一手觀察，AI 判斷重要參考）
        notes = (p.get("notes") or "").strip()
        notes_line = f"  · 備註：{notes}" if notes else ""

        block = "\n".join(x for x in [header, triage_line, vital_line, gps_line, notes_line] if x)
        lines.append(block)

    return "\n\n".join(lines)


# ── CLI 測試 ───────────────────────────────────────────────

if __name__ == "__main__":
    # 範例 A — 重傷但好救（預期高優先）
    patient_a = {
        "id": "傷員A", "location": "A區",
        "breathing_rate": 35, "capillary_refill": 1.0, "can_follow_commands": True,
        # 六維度
        "breathing_difficulty": True,
        "heavy_bleeding": True,
        "deteriorate_1h": True,
        "high_survival": True,
    }

    # 範例 B — 嚴重且難救（預期低優先）
    patient_b = {
        "id": "傷員B", "location": "B區",
        "breathing_rate": 20, "capillary_refill": -1, "can_follow_commands": True,
        # 六維度
        "severe_injury": True,
        "very_low_survival": True,
        "rescue_long_time": True,
        "rescue_heavy_equipment": True,
        "env_inaccessible": True,
    }

    # 範例 C — 輕傷
    patient_c = {
        "id": "傷員C", "location": "C區",
        "breathing_rate": 18, "capillary_refill": 1.0, "can_follow_commands": True,
        "minor_injury": True,
        "condition_stable": True,
        "high_survival": True,
    }

    ranked = rank_patients([patient_a, patient_b, patient_c])
    for p in ranked:
        print(f"#{p['rank']} [{p['id']}] {p['priority']} "
              f"總分={p['total_score']} (START={p['start_bonus']}, "
              f"維度={p['dimension_score']})")
        for d in p["dimensions"]:
            print(f"    {d['dimension']}: {d['item']} "
                  f"({d['raw']}×{d['weight']}={d['weighted']})")

    print("\n--- LLM Prompt ---")
    print(format_for_llm(ranked))
