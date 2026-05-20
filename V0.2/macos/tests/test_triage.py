"""
Tests for triage scoring engine — START classification + six-dimension weighted scoring.
"""
import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from triage import (
    triage_START, format_for_llm,
    score_dimensions, calculate_total_score, rank_patients, DIMENSIONS,
)


# ---------------------------------------------------------------------------
# triage_START – START 三步驟分類
# ---------------------------------------------------------------------------

class TestTriageSTART:
    """Branch coverage for the five decision paths in triage_START."""

    def test_no_breathing_returns_black(self):
        """breathing_rate == -1 → 黑色 (DECEASED)."""
        result = triage_START({"breathing_rate": -1})
        assert result["priority"] == "黑色"
        assert result["start_bonus"] == -200

    def test_rapid_breathing_returns_red(self):
        """breathing_rate > 30 → 紅色 (IMMEDIATE)."""
        result = triage_START({"breathing_rate": 31})
        assert result["priority"] == "紅色"
        assert result["start_bonus"] == 60

    def test_breathing_exactly_30_does_not_trigger_rapid(self):
        result = triage_START({
            "breathing_rate": 30,
            "capillary_refill": 1.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"
        assert result["start_bonus"] == 0

    def test_capillary_refill_over_two_returns_red(self):
        result = triage_START({
            "breathing_rate": 16,
            "capillary_refill": 2.1,
            "can_follow_commands": True,
        })
        assert result["priority"] == "紅色"
        assert result["start_bonus"] == 60

    def test_capillary_refill_exactly_two_is_normal(self):
        result = triage_START({
            "breathing_rate": 16,
            "capillary_refill": 2.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"

    def test_no_pulse_capillary_minus_one_returns_red(self):
        result = triage_START({
            "breathing_rate": 20,
            "capillary_refill": -1,
            "can_follow_commands": True,
        })
        assert result["priority"] == "紅色"

    def test_cannot_follow_commands_returns_red_per_spec(self):
        """can_follow_commands == False → 紅色."""
        result = triage_START({
            "breathing_rate": 18,
            "capillary_refill": 1.5,
            "can_follow_commands": False,
        })
        assert result["priority"] == "紅色"
        assert result["start_bonus"] == 60

    def test_all_normal_returns_green(self):
        result = triage_START({
            "breathing_rate": 18,
            "capillary_refill": 1.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"
        assert result["start_bonus"] == 0

    def test_missing_fields_use_defaults(self):
        result = triage_START({})
        assert result["priority"] == "綠色"

    def test_result_contains_required_keys(self):
        result = triage_START({"breathing_rate": -1})
        assert "priority" in result
        assert "reason" in result
        assert "start_bonus" in result

    def test_high_breathing_boundary(self):
        assert triage_START({"breathing_rate": 30, "capillary_refill": 1.0, "can_follow_commands": True})["priority"] == "綠色"
        assert triage_START({"breathing_rate": 31})["priority"] == "紅色"

    def test_breathing_rate_zero_is_not_minus_one(self):
        result = triage_START({
            "breathing_rate": 0,
            "capillary_refill": 1.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"


# ---------------------------------------------------------------------------
# score_dimensions – 六維度加權評分
# ---------------------------------------------------------------------------

class TestScoreDimensions:

    def test_empty_patient_returns_zero(self):
        total, details = score_dimensions({})
        assert total == 0.0
        assert details == []

    def test_single_vitals_item(self):
        total, details = score_dimensions({"breathing_difficulty": True})
        assert total == pytest.approx(40 * 1.5)  # 60.0
        assert len(details) == 1
        assert details[0]["dimension"] == "生命危急程度"

    def test_multiple_vitals_items_sum(self):
        """同維度多項同時符合時依範例全部計入。"""
        total, _ = score_dimensions({
            "breathing_difficulty": True,
            "heavy_bleeding": True,
        })
        assert total == pytest.approx(40 * 1.5 + 50 * 1.5)  # 135.0

    def test_rescue_cost_negative(self):
        total, _ = score_dimensions({
            "rescue_long_time": True,
            "rescue_heavy_equipment": True,
        })
        assert total == pytest.approx(-30 * 1.0 + -20 * 1.0)  # -50.0

    def test_cross_dimension_sum(self):
        total, _ = score_dimensions({
            "heavy_bleeding": True,      # 50 × 1.5 = 75
            "deteriorate_1h": True,      # 40 × 1.4 = 56
            "high_survival": True,       # 30 × 1.3 = 39
        })
        assert total == pytest.approx(75 + 56 + 39)

    def test_false_flag_not_counted(self):
        total, _ = score_dimensions({"breathing_difficulty": False})
        assert total == 0.0

    def test_environment_negative_item(self):
        total, _ = score_dimensions({"env_inaccessible": True})
        assert total == pytest.approx(-20 * 1.1)  # -22.0


# ---------------------------------------------------------------------------
# calculate_total_score – START + 六維度
# ---------------------------------------------------------------------------

class TestCalculateTotalScore:

    def test_example_a_heavy_injury_good_rescue(self):
        """規範範例 A：重傷但好救 → +290 分。"""
        patient_a = {
            "breathing_rate": 35,  # IMMEDIATE → +60
            "capillary_refill": 1.0,
            "can_follow_commands": True,
            "breathing_difficulty": True,   # 40 × 1.5 = 60
            "heavy_bleeding": True,         # 50 × 1.5 = 75
            "deteriorate_1h": True,         # 40 × 1.4 = 56
            "high_survival": True,          # 30 × 1.3 = 39
        }
        result = calculate_total_score(patient_a)
        assert result["priority"] == "紅色"
        assert result["start_bonus"] == 60
        assert result["total_score"] == pytest.approx(290.0)

    def test_example_b_severe_hard_rescue(self):
        """規範範例 B：嚴重且難救 → -16 分。"""
        patient_b = {
            "breathing_rate": 20,
            "capillary_refill": -1,  # IMMEDIATE → +60
            "can_follow_commands": True,
            "severe_injury": True,           # 40 × 1.2 = 48
            "very_low_survival": True,       # -40 × 1.3 = -52
            "rescue_long_time": True,        # -30 × 1.0 = -30
            "rescue_heavy_equipment": True,  # -20 × 1.0 = -20
            "env_inaccessible": True,        # -20 × 1.1 = -22
        }
        result = calculate_total_score(patient_b)
        assert result["priority"] == "紅色"
        assert result["start_bonus"] == 60
        assert result["total_score"] == pytest.approx(-16.0)

    def test_deceased_extremely_low_score(self):
        result = calculate_total_score({"breathing_rate": -1})
        assert result["priority"] == "黑色"
        assert result["start_bonus"] == -200
        assert result["total_score"] == -200.0

    def test_green_no_dimensions_zero_score(self):
        result = calculate_total_score({
            "breathing_rate": 18,
            "capillary_refill": 1.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"
        assert result["total_score"] == 0.0


# ---------------------------------------------------------------------------
# rank_patients – 救援優先序
# ---------------------------------------------------------------------------

class TestRankPatients:

    def test_a_before_b(self):
        """範例 A(+290) 排在 B(-16) 前面。"""
        patients = [
            {
                "id": "B", "breathing_rate": 20, "capillary_refill": -1,
                "can_follow_commands": True,
                "severe_injury": True, "very_low_survival": True,
                "rescue_long_time": True, "rescue_heavy_equipment": True,
                "env_inaccessible": True,
            },
            {
                "id": "A", "breathing_rate": 35, "capillary_refill": 1.0,
                "can_follow_commands": True,
                "breathing_difficulty": True, "heavy_bleeding": True,
                "deteriorate_1h": True, "high_survival": True,
            },
        ]
        ranked = rank_patients(patients)
        assert ranked[0]["id"] == "A"
        assert ranked[1]["id"] == "B"
        assert ranked[0]["rank"] == 1
        assert ranked[1]["rank"] == 2

    def test_same_score_red_before_green(self):
        """同分時 紅色 優先於 綠色。"""
        # Red: start_bonus=60, dim=20*1.2=24, total=84
        p_red = {"breathing_rate": 31, "can_follow_commands": True, "moderate_injury": True}
        # Green: start_bonus=0, dim=30*1.3+30*1.5=84, total=84
        p_green = {
            "breathing_rate": 18, "capillary_refill": 1.0,
            "can_follow_commands": True,
            "high_survival": True,   # 30 * 1.3 = 39
            "unconscious": True      # 30 * 1.5 = 45 -> 39+45 = 84
        }
        ranked = rank_patients([p_green, p_red])
        assert ranked[0]["total_score"] == ranked[1]["total_score"]
        assert ranked[0]["priority"] == "紅色"

    def test_deceased_last(self):
        patients = [
            {"id": "dead", "breathing_rate": -1},
            {"id": "minor", "breathing_rate": 18, "capillary_refill": 1.0, "can_follow_commands": True},
        ]
        ranked = rank_patients(patients)
        assert ranked[-1]["id"] == "dead"

    def test_empty_list(self):
        assert rank_patients([]) == []

    def test_single_patient_gets_rank_1(self):
        ranked = rank_patients([{"id": "solo", "breathing_rate": 20, "capillary_refill": 1.0, "can_follow_commands": True}])
        assert len(ranked) == 1
        assert ranked[0]["rank"] == 1


# ---------------------------------------------------------------------------
# format_for_llm – 格式化
# ---------------------------------------------------------------------------

class TestFormatForLLM:

    def test_empty_list_returns_empty_string(self):
        assert format_for_llm([]) == ""

    def test_single_patient_format(self):
        patients = [{
            "id": "傷員A",
            "location": "北區",
            "priority": "紅色",
            "reason": "呼吸過速",
        }]
        output = format_for_llm(patients)
        assert "[傷員A]" in output
        assert "紅色" in output
        assert "北區" in output

    def test_format_with_score(self):
        patients = [{
            "id": "P1", "location": "A", "priority": "紅色",
            "reason": "test", "total_score": 290.0, "rank": 1,
        }]
        output = format_for_llm(patients)
        assert "290" in output
        assert "#1" in output

    def test_multiple_patients_produces_multiple_blocks(self):
        patients = [
            {"id": "P1", "location": "A", "priority": "黑色", "reason": "x"},
            {"id": "P2", "location": "B", "priority": "綠色", "reason": "y"},
        ]
        # 新格式：每位傷患為一個多行 block，以雙換行分隔
        blocks = format_for_llm(patients).split("\n\n")
        assert len(blocks) == 2

    def test_missing_id_falls_back_to_numbered_label(self):
        patients = [{"location": "Z", "priority": "綠色", "reason": "ok"}]
        output = format_for_llm(patients)
        assert "[傷員1]" in output

    def test_missing_location_falls_back(self):
        patients = [{"id": "X", "priority": "綠色", "reason": "ok"}]
        output = format_for_llm(patients)
        assert "未知區" in output

    def test_missing_priority_and_reason_fall_back(self):
        patients = [{"id": "X", "location": "Loc"}]
        output = format_for_llm(patients)
        assert "未知" in output
        assert "無" in output


# ---------------------------------------------------------------------------
# DIMENSIONS 定義完整性
# ---------------------------------------------------------------------------

class TestDimensionsConfig:

    def test_six_dimensions_exist(self):
        assert len(DIMENSIONS) == 6

    def test_all_dimensions_have_weight_and_items(self):
        for key, cfg in DIMENSIONS.items():
            assert "weight" in cfg, f"{key} missing weight"
            assert "items" in cfg, f"{key} missing items"
            assert isinstance(cfg["weight"], (int, float))
            assert len(cfg["items"]) > 0
