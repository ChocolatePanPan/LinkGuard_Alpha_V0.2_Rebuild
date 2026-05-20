"""
pws_fetcher.py — Public Warning System (災防告警) 整合模組
串接中央氣象署開放資料 API，取得地震速報與颱風警報，
轉換為 LinkGuard PWSAlert 格式。

AlertType mapping：
  earthquake / aftershock / tsunami / typhoon / flood / landslide / other
Severity mapping：
  info / minor / moderate / severe / extreme
"""
from __future__ import annotations

import os
import time
from datetime import datetime, timezone, timedelta
from typing import Any

import certifi
import requests

_CWA_BASE = "https://opendata.cwa.gov.tw/api/v1/rest/datastore"

# 每次拉取後快取，避免重複廣播相同警報
_seen_ids: set[str] = set()

TW = timezone(timedelta(hours=8))


def _get(endpoint: str, api_key: str, params: dict | None = None) -> dict | None:
    url = f"{_CWA_BASE}/{endpoint}"
    try:
        resp = requests.get(
            url,
            headers={"Authorization": api_key},
            params=params or {},
            timeout=15,
            verify=certifi.where(),
        )
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"[pws_fetcher] GET {endpoint} 失敗: {e}")
        return None


def _fetch_earthquakes(api_key: str) -> list[dict]:
    """取得顯著有感地震（M ≥ 4.0）"""
    alerts: list[dict] = []

    if os.environ.get("PWS_OFFLINE_MOCK"):
        return []

    data = _get("E-A0015-001", api_key, {"limit": 5})
    if not data:
        return alerts

    records = (data.get("records") or {}).get("Earthquake") or []
    for eq in records:
        eq_no = str(eq.get("EarthquakeNo", ""))
        uid = f"eq-{eq_no}"
        if uid in _seen_ids:
            continue

        info = eq.get("EarthquakeInfo", {})
        ep = info.get("Epicenter", {})
        mag = info.get("EarthquakeMagnitude", {}).get("MagnitudeValue", 0.0)
        depth = info.get("FocalDepth", 0)
        loc = ep.get("Location", "")
        origin_time = info.get("OriginTime", "")

        # 嚴重度依規模
        if mag >= 6.5:
            severity = "extreme"
        elif mag >= 6.0:
            severity = "severe"
        elif mag >= 5.0:
            severity = "moderate"
        elif mag >= 4.0:
            severity = "minor"
        else:
            continue  # 小於 4.0 略過

        alert_type = "earthquake"
        title = f"地震速報 M{mag:.1f}"
        content = f"震央：{loc}｜深度：{depth} km｜時間：{origin_time}"

        _seen_ids.add(uid)
        alerts.append({
            "id": uid,
            "alertType": alert_type,
            "title": title,
            "content": content,
            "severity": severity,
            "publisher": "中央氣象署",
            "publishTime": time.time(),
            "isActive": True,
        })

    return alerts


def _fetch_typhoon(api_key: str) -> list[dict]:
    """取得颱風警報（有警報時才回傳）"""
    alerts: list[dict] = []

    if os.environ.get("PWS_OFFLINE_MOCK"):
        return []

    data = _get("W-C0033-001", api_key)
    if not data:
        return alerts

    records = data.get("records") or {}
    typhoon_list = records.get("tropicalCyclones", {}).get("tropicalCyclone") or []
    if isinstance(typhoon_list, dict):
        typhoon_list = [typhoon_list]

    for tc in typhoon_list:
        cwa_id = str(tc.get("cwaTyphoonID", tc.get("id", "")))
        uid = f"ty-{cwa_id}"
        if uid in _seen_ids:
            continue

        name = tc.get("typhoonName", "颱風")
        status = tc.get("typhoonStatus", "")
        # 有陸警/海警才廣播
        if "警報" not in status and "Warning" not in status:
            continue

        intensity = tc.get("typhoonIntensity", "")
        if "強烈" in intensity:
            severity = "extreme"
        elif "中度" in intensity:
            severity = "severe"
        else:
            severity = "moderate"

        _seen_ids.add(uid)
        alerts.append({
            "id": uid,
            "alertType": "typhoon",
            "title": f"{name}颱風警報",
            "content": f"狀態：{status}｜強度：{intensity}",
            "severity": severity,
            "publisher": "中央氣象署",
            "publishTime": time.time(),
            "isActive": True,
        })

    return alerts


def fetch_pws_alerts(api_key: str | None = None) -> list[dict]:
    """
    主函式：拉取所有 PWS 警報（地震 + 颱風）。
    只回傳「尚未見過」的新警報（基於 _seen_ids 快取）。
    """
    api_key = api_key or os.environ.get(
        "CWA_API_KEY", "CWA-ABB1DE38-E0CD-4EBA-9723-894AAA62AE5E"
    )
    results: list[dict] = []
    results.extend(_fetch_earthquakes(api_key))
    results.extend(_fetch_typhoon(api_key))
    return results


def reset_seen_ids() -> None:
    """測試用：清除快取"""
    _seen_ids.clear()


if __name__ == "__main__":
    alerts = fetch_pws_alerts()
    if alerts:
        for a in alerts:
            print(f"[PWS] {a['alertType'].upper()} {a['severity']:8s} {a['title']}")
            print(f"      {a['content']}")
    else:
        print("[PWS] 目前無新 PWS 警報")
