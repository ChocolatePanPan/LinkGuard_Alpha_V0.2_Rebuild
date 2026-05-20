"""
triage.py — START 檢傷分類（向下相容入口）
完整評分引擎位於 start_triage.py
"""
from start_triage import (                          # noqa: F401
    triage_START,
    score_dimensions,
    calculate_total_score,
    rank_patients,
    format_for_llm,
    DIMENSIONS,
)


if __name__ == "__main__":
    # 測試案例
    patients_data = [
        {
            "id": "傷員1", "location": "A區",
            "breathing_rate": -1, "capillary_refill": 0, "can_follow_commands": False,
        },
        {
            "id": "傷員2", "location": "B區",
            "breathing_rate": 20, "capillary_refill": 1.5, "can_follow_commands": False,
        },
        {
            "id": "傷員3", "location": "C區",
            "breathing_rate": 18, "capillary_refill": 1.0, "can_follow_commands": True,
        },
    ]

    triage_results = []
    for p in patients_data:
        result = triage_START(p)
        combined = {**p, **result}
        triage_results.append(combined)
        print(f"{p['id']}: {result['priority']} — {result['reason']} (START加成={result['start_bonus']})")

    print("\n--- LLM Prompt ---")
    print(format_for_llm(triage_results))
