import os

import certifi
import requests


def fetch_weather(station_id: str, api_key: str) -> dict | None:
    """從中央氣象署開放資料API取得自動氣象站觀測資料

    Args:
        station_id: 測站代碼（如 "C0A980"）
        api_key: 中央氣象署 API 授權碼

    Returns:
        氣象觀測 dict，或 API 失敗時回傳 None
    """
    # 離線模式：回傳模擬氣象資料
    if os.environ.get("OFFLINE_WEATHER_MOCK"):
        return {
            "temperature": 28.0,
            "humidity": 75.0,
            "wind_speed": 3.2,
            "rainfall": 0.0,
            "timestamp": "",
            "station_id": station_id,
        }

    url = "https://opendata.cwa.gov.tw/api/v1/rest/datastore/O-A0001-001"
    headers = {"Authorization": api_key}
    params = {"StationId": station_id}

    try:
        resp = requests.get(
            url, headers=headers, params=params, timeout=10,
            verify=certifi.where(),
        )
        resp.raise_for_status()
        data = resp.json()

        stations = data.get("records", {}).get("Station", [])
        if not stations:
            print(f"[pws_fetcher] 找不到測站 {station_id} 的資料")
            return None

        station = stations[0]
        obs = station.get("WeatherElement", {})

        result = {
            "temperature": float(obs.get("AirTemperature", 0)),
            "humidity": float(obs.get("RelativeHumidity", 0)),
            "wind_speed": float(obs.get("WindSpeed", 0)),
            "rainfall": float(obs.get("Now", {}).get("Precipitation", 0)),
            "timestamp": station.get("ObsTime", {}).get("DateTime", ""),
            "station_id": station_id,
        }

        # 儲存氣象歷史到統一資料庫
        try:
            import linkguard_db
            linkguard_db.save_weather(result)
        except Exception:
            pass  # DB 儲存失敗不影響氣象資料回傳

        return result
    except Exception as e:
        print(f"[pws_fetcher] API請求失敗: {e}")
        return None


def format_weather_for_llm(weather: dict) -> str:
    """將氣象資料格式化為LLM prompt字串"""
    return (
        f"氣溫:{weather.get('temperature', 'N/A')}°C | "
        f"濕度:{weather.get('humidity', 'N/A')}% | "
        f"風速:{weather.get('wind_speed', 'N/A')}m/s | "
        f"雨量:{weather.get('rainfall', 'N/A')}mm"
    )


if __name__ == "__main__":
    import sys

    # 用法: python pws_fetcher.py <測站ID> <API_KEY>
    api_key = os.environ.get("CWA_API_KEY", "CWA-ABB1DE38-E0CD-4EBA-9723-894AAA62AE5E")
    station_id = "C0A980"

    if len(sys.argv) >= 3:
        station_id = sys.argv[1]
        api_key = sys.argv[2]

    print(f"[pws_fetcher] 查詢測站 {station_id} ...")
    weather = fetch_weather(station_id, api_key)

    if weather:
        print(f"觀測時間: {weather['timestamp']}")
        print(format_weather_for_llm(weather))
    else:
        print("無法取得氣象資料")
