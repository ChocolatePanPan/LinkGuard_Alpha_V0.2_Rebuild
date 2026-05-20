"""
Tests for start_triage.py – the enhanced START triage module used by qwen_server.
The logic is identical to triage.py but the Chinese reason strings differ slightly.
"""
import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from start_triage import triage_START, format_for_llm


# ---------------------------------------------------------------------------
# triage_START
# ---------------------------------------------------------------------------

class TestStartTriageSTART:

    def test_no_breathing_black(self):
        result = triage_START({"breathing_rate": -1})
        assert result["priority"] == "黑色"
        assert "呼吸" in result["reason"]

    def test_rapid_breathing_red(self):
        result = triage_START({"breathing_rate": 32})
        assert result["priority"] == "紅色"
        assert "30" in result["reason"]

    def test_capillary_refill_gt_two_red(self):
        result = triage_START({
            "breathing_rate": 18,
            "capillary_refill": 3.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "紅色"

    def test_no_pulse_capillary_minus_one_red(self):
        result = triage_START({
            "breathing_rate": 18,
            "capillary_refill": -1,
            "can_follow_commands": True,
        })
        assert result["priority"] == "紅色"

    def test_cannot_follow_commands_red(self):
        result = triage_START({
            "breathing_rate": 18,
            "capillary_refill": 1.0,
            "can_follow_commands": False,
        })
        assert result["priority"] == "紅色"
        assert "指令" in result["reason"]

    def test_all_normal_green(self):
        result = triage_START({
            "breathing_rate": 18,
            "capillary_refill": 1.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"
        assert "正常" in result["reason"]

    def test_defaults_give_green(self):
        """Empty dict should use safe defaults and result in 綠色."""
        result = triage_START({})
        assert result["priority"] == "綠色"

    def test_priority_ordering_breathing_checked_first(self):
        """When breathing_rate == -1 all other fields are irrelevant."""
        result = triage_START({
            "breathing_rate": -1,
            "capillary_refill": -1,
            "can_follow_commands": False,
        })
        assert result["priority"] == "黑色"

    def test_priority_ordering_breathing_rate_before_capillary(self):
        """breathing_rate > 30 is checked before capillary_refill."""
        result = triage_START({
            "breathing_rate": 40,
            "capillary_refill": -1,
            "can_follow_commands": True,
        })
        assert result["priority"] == "紅色"
        assert "30" in result["reason"]

    def test_capillary_exactly_two_normal_path(self):
        result = triage_START({
            "breathing_rate": 16,
            "capillary_refill": 2.0,
            "can_follow_commands": True,
        })
        assert result["priority"] == "綠色"


# ---------------------------------------------------------------------------
# format_for_llm
# ---------------------------------------------------------------------------

class TestStartFormatForLLM:

    def test_empty_list(self):
        assert format_for_llm([]) == ""

    def test_output_contains_all_fields(self):
        patients = [{
            "id": "傷員1",
            "location": "A區",
            "priority": "紅色",
            "reason": "呼吸過速",
        }]
        out = format_for_llm(patients)
        assert "傷員1" in out
        assert "A區" in out
        assert "紅色" in out
        assert "呼吸過速" in out

    def test_block_count_matches_patient_count(self):
        patients = [
            {"id": f"P{i}", "location": "X", "priority": "綠色", "reason": "ok"}
            for i in range(5)
        ]
        # 新格式：每位傷患為一個多行 block，以雙換行分隔
        blocks = format_for_llm(patients).strip().split("\n\n")
        assert len(blocks) == 5

    def test_fallback_id_for_missing_id(self):
        patients = [{"location": "Loc", "priority": "黑色", "reason": "none"}]
        out = format_for_llm(patients)
        assert "傷員1" in out

    def test_separator_format(self):
        """Lines should use the pipe-separated format."""
        patients = [{"id": "A", "location": "B", "priority": "綠色", "reason": "ok"}]
        out = format_for_llm(patients)
        assert "|" in out
