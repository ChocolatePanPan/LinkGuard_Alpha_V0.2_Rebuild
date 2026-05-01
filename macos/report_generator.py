"""
report_generator.py — LinkGuard 自動事件報告生成
使用 fpdf2 生成 PDF 報告
整合進 http_server.py 的 endpoint
"""

import json
import os
from datetime import datetime, timezone, timedelta
from pathlib import Path

from fpdf import FPDF

import linkguard_db
from utils import now_iso

TZ_TW = timezone(timedelta(hours=8))
REPORT_DIR = Path("./reports")
PHOTO_DIR = Path("./photos")



class LinkGuardReport(FPDF):
    """自訂 PDF 報告"""

    def __init__(self):
        super().__init__()
        self._setup_fonts()

    def _setup_fonts(self):
        """設置中文字體 — 使用內建字體（展示用）"""
        # fpdf2 內建 Helvetica，中文部分用 unicode fallback
        # 若需完整中文支援，可載入 .ttf 字體
        font_path = os.path.join(os.path.dirname(__file__), "fonts")
        if os.path.isdir(font_path):
            for f in os.listdir(font_path):
                if f.endswith(".ttf"):
                    self.add_font(f[:-4], "", os.path.join(font_path, f), uni=True)
                    return
        # fallback: 使用 fpdf2 內建 helvetica（英文+數字正常，中文會變問號）
        # 建議放入 NotoSansCJK-Regular.ttf 到 fonts/ 目錄

    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(100, 100, 100)
        self.cell(0, 8, "LinkGuard Disaster Response Report", align="R")
        self.ln(10)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    def chapter_title(self, title: str):
        self.set_font("Helvetica", "B", 16)
        self.set_text_color(30, 30, 30)
        self.cell(0, 12, title, new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(0, 120, 60)
        self.set_line_width(0.8)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(6)

    def section_title(self, title: str):
        self.set_font("Helvetica", "B", 12)
        self.set_text_color(50, 50, 50)
        self.cell(0, 8, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def body_text(self, text: str):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(60, 60, 60)
        self.multi_cell(0, 6, text)
        self.ln(2)

    def stat_row(self, label: str, value: str):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(60, 60, 60)
        self.cell(60, 7, label)
        self.set_font("Helvetica", "", 10)
        self.cell(0, 7, value, new_x="LMARGIN", new_y="NEXT")


def generate_report(
    event_name: str,
    start_time: str = "",
    end_time: str = "",
    include_photos: bool = True,
    include_audio: bool = True,
) -> str:
    """生成完整 PDF 事件報告，回傳檔案路徑"""

    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    if not end_time:
        end_time = now_iso()
    if not start_time:
        start_time = (datetime.now(TZ_TW) - timedelta(hours=24)).isoformat()

    pdf = LinkGuardReport()
    pdf.alias_nb_pages()

    # === 第 1 頁：封面 ===
    pdf.add_page()
    pdf.ln(40)
    pdf.set_font("Helvetica", "B", 28)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 15, "LinkGuard", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 14)
    pdf.set_text_color(80, 80, 80)
    pdf.cell(0, 10, "Disaster Response System - Event Report", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(20)
    pdf.set_font("Helvetica", "B", 18)
    pdf.set_text_color(30, 30, 30)
    pdf.cell(0, 12, event_name, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)
    pdf.set_font("Helvetica", "", 11)
    pdf.set_text_color(100, 100, 100)
    pdf.cell(0, 8, f"Time Range: {start_time[:19]} ~ {end_time[:19]}", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, f"Generated: {now_iso()[:19]}", align="C",
             new_x="LMARGIN", new_y="NEXT")

    # === 第 2 頁：事件摘要 ===
    pdf.add_page()
    pdf.chapter_title("Event Summary")

    patients = linkguard_db.get_all_patients()
    patient_stats = linkguard_db.get_patient_stats()
    decisions = linkguard_db.get_recent_decisions(n=9999)
    reports = linkguard_db.get_reports(limit=9999)
    events = linkguard_db.get_events_since(start_time)
    photos = linkguard_db.get_photos(limit=9999)
    resources = linkguard_db.get_all_resources()
    resource_summary = linkguard_db.get_resource_summary()

    sos_count = sum(1 for e in events if e.get("event_type") == "sos")

    pdf.section_title("Patient Statistics")
    pdf.stat_row("Total Patients:", str(patient_stats["total"]))
    pdf.stat_row("Red (Immediate):", str(patient_stats["red"]))
    pdf.stat_row("Yellow (Delayed):", str(patient_stats["yellow"]))
    pdf.stat_row("Green (Minor):", str(patient_stats["green"]))
    pdf.stat_row("Black (Deceased):", str(patient_stats["black"]))
    pdf.ln(4)

    pdf.section_title("Event Metrics")
    pdf.stat_row("SOS Events:", str(sos_count))
    pdf.stat_row("Reports Filed:", str(len(reports)))
    pdf.stat_row("AI Decisions:", str(len(decisions)))
    pdf.stat_row("Photos Taken:", str(len(photos)))
    pdf.stat_row("System Events:", str(len(events)))
    pdf.ln(4)

    if resources:
        pdf.section_title("Resources")
        for rtype, info in resource_summary.items():
            pdf.stat_row(f"{rtype}:", f"{info['available']}/{info['total']} available")
        pdf.ln(4)

    # === 第 3 頁起：傷患完整記錄 ===
    if patients:
        pdf.add_page()
        pdf.chapter_title("Patient Records")
        for i, p in enumerate(patients):
            if pdf.get_y() > 250:
                pdf.add_page()
            pdf.section_title(f"Patient: {p.get('patient_id', f'P-{i+1}')}")
            pdf.stat_row("Priority:", p.get("priority", "N/A"))
            pdf.stat_row("Reason:", p.get("reason", "N/A"))
            pdf.stat_row("Location:", p.get("location_desc", "N/A"))
            lat = p.get("location_lat", "")
            lon = p.get("location_lon", "")
            if lat and lon:
                pdf.stat_row("GPS:", f"({lat}, {lon})")
            pdf.stat_row("Breathing Rate:", str(p.get("breathing_rate", "N/A")))
            pdf.stat_row("Capillary Refill:", str(p.get("capillary_refill", "N/A")))
            cmd = p.get("can_follow_commands")
            pdf.stat_row("Follow Commands:", "Yes" if cmd else "No")
            pdf.stat_row("Timestamp:", p.get("timestamp", "N/A")[:19])
            if p.get("notes"):
                pdf.stat_row("Notes:", p["notes"])
            pdf.ln(4)

    # === AI 決策記錄 ===
    if decisions:
        pdf.add_page()
        pdf.chapter_title("AI Decision History")
        for d in decisions[-20:]:  # 最近 20 筆
            if pdf.get_y() > 240:
                pdf.add_page()
            pdf.section_title(f"Decision [{d.get('timestamp', '')[:19]}]")
            pdf.stat_row("Trigger:", d.get("trigger_type", "N/A"))
            text = d.get("decision_text", "")
            if len(text) > 500:
                text = text[:500] + "..."
            pdf.body_text(text)
            pdf.ln(2)

    # === 語音轉錄記錄 ===
    if include_audio:
        transcriptions = linkguard_db.get_transcriptions(limit=100)
        if transcriptions:
            pdf.add_page()
            pdf.chapter_title("Voice Transcriptions")
            for t in transcriptions:
                if pdf.get_y() > 250:
                    pdf.add_page()
                pdf.stat_row("Time:", t.get("timestamp", "")[:19])
                pdf.stat_row("Sender:", t.get("sender_id", "N/A"))
                pdf.stat_row("Source:", t.get("source", "N/A"))
                text = t.get("text", "")
                if text:
                    pdf.body_text(text)
                pdf.ln(2)

    # === 事件時間軸 ===
    if events:
        pdf.add_page()
        pdf.chapter_title("Event Timeline")
        for e in events[-50:]:  # 最近 50 筆
            if pdf.get_y() > 260:
                pdf.add_page()
            ts = e.get("timestamp", "")[:19]
            etype = e.get("event_type", "")
            desc = e.get("description", "")
            severity = e.get("severity", "info")
            line = f"[{ts}] [{severity.upper()}] {etype}: {desc}"
            if len(line) > 120:
                line = line[:120] + "..."
            pdf.body_text(line)

    # === 照片記錄 ===
    if include_photos and photos:
        pdf.add_page()
        pdf.chapter_title("Photo Records")
        for p in photos:
            if pdf.get_y() > 240:
                pdf.add_page()
            pdf.section_title(f"Photo: {p.get('photo_id', '')}")
            pdf.stat_row("Sender:", p.get("sender_name", "N/A"))
            pdf.stat_row("Location:", p.get("location_desc", "N/A"))
            lat = p.get("lat", "")
            lon = p.get("lon", "")
            if lat and lon:
                pdf.stat_row("GPS:", f"({lat}, {lon})")
            if p.get("caption"):
                pdf.stat_row("Caption:", p["caption"])
            pdf.stat_row("Time:", p.get("timestamp", "")[:19])

            # 嵌入照片（如果檔案存在）
            photo_path = PHOTO_DIR / f"{p.get('photo_id', '')}.jpg"
            if photo_path.exists():
                try:
                    pdf.image(str(photo_path), w=80)
                except Exception:
                    pdf.body_text("[Photo file could not be embedded]")
            pdf.ln(4)

    # === 輸出 PDF ===
    ts = datetime.now(TZ_TW).strftime("%Y%m%d_%H%M%S")
    filename = f"event_{ts}.pdf"
    filepath = REPORT_DIR / filename
    pdf.output(str(filepath))

    # USB 備份
    try:
        from usb_backup import sync_report_pdf
        sync_report_pdf(filename)
    except Exception as e:
        print(f"[REPORT] USB 備份失敗: {e}")

    print(f"[REPORT] PDF 報告已生成: {filepath}")
    return str(filepath)


if __name__ == "__main__":
    linkguard_db.init_db()
    path = generate_report("LinkGuard System Test")
    print(f"Report saved to: {path}")
