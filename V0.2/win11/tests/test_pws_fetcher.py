"""
Tests for pws_fetcher.py – weather API client and LLM formatter.
All HTTP calls are mocked with unittest.mock so no real network access occurs.
"""
import sys
import os
import pytest
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pws_fetcher import fetch_weather, format_weather_for_llm


def _make_response(stations: list, status_code: int = 200):
    """Helper: build a mock requests.Response with the CWA JSON structure."""
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = {"records": {"Station": stations}}
    resp.raise_for_status.return_value = None
    return resp


def _station(temperature=25.3, humidity=70, wind_speed=3.5,
             precipitation=0.0, obs_time="2024-01-01T12:00:00+08:00"):
    return {
        "ObsTime": {"DateTime": obs_time},
        "WeatherElement": {
            "AirTemperature": str(temperature),
            "RelativeHumidity": str(humidity),
            "WindSpeed": str(wind_speed),
            "Now": {"Precipitation": str(precipitation)},
        },
    }


# ---------------------------------------------------------------------------
# fetch_weather
# ---------------------------------------------------------------------------

class TestFetchWeather:

    @patch("pws_fetcher.requests.get")
    def test_successful_fetch_returns_dict(self, mock_get):
        mock_get.return_value = _make_response([_station()])
        result = fetch_weather("C0A980", "FAKE_KEY")
        assert result is not None
        assert result["temperature"] == 25.3
        assert result["humidity"] == 70.0
        assert result["wind_speed"] == 3.5
        assert result["rainfall"] == 0.0
        assert result["timestamp"] == "2024-01-01T12:00:00+08:00"

    @patch("pws_fetcher.requests.get")
    def test_requests_get_called_with_correct_params(self, mock_get):
        mock_get.return_value = _make_response([_station()])
        fetch_weather("C0A980", "MY_KEY")
        args, kwargs = mock_get.call_args
        assert kwargs.get("params", {}).get("StationId") == "C0A980"
        assert kwargs.get("headers", {}).get("Authorization") == "MY_KEY"

    @patch("pws_fetcher.requests.get")
    def test_empty_station_list_returns_none(self, mock_get):
        mock_get.return_value = _make_response([])
        result = fetch_weather("C0A980", "FAKE_KEY")
        assert result is None

    @patch("pws_fetcher.requests.get")
    def test_http_error_returns_none(self, mock_get):
        import requests as req_lib
        mock_get.return_value = MagicMock(
            raise_for_status=MagicMock(
                side_effect=req_lib.exceptions.HTTPError("404")
            )
        )
        result = fetch_weather("INVALID", "FAKE_KEY")
        assert result is None

    @patch("pws_fetcher.requests.get", side_effect=ConnectionError("timeout"))
    def test_connection_error_returns_none(self, mock_get):
        result = fetch_weather("C0A980", "FAKE_KEY")
        assert result is None

    @patch("pws_fetcher.requests.get")
    def test_missing_weather_element_fields_default_to_zero(self, mock_get):
        """A station with empty WeatherElement should return zeros, not crash."""
        station = {
            "ObsTime": {"DateTime": ""},
            "WeatherElement": {},
        }
        mock_get.return_value = _make_response([station])
        result = fetch_weather("C0A980", "FAKE_KEY")
        assert result is not None
        assert result["temperature"] == 0.0
        assert result["humidity"] == 0.0
        assert result["wind_speed"] == 0.0
        assert result["rainfall"] == 0.0

    @patch("pws_fetcher.requests.get")
    def test_returns_first_station_when_multiple_exist(self, mock_get):
        stations = [
            _station(temperature=10.0),
            _station(temperature=99.0),
        ]
        mock_get.return_value = _make_response(stations)
        result = fetch_weather("C0A980", "FAKE_KEY")
        assert result["temperature"] == 10.0

    @patch("pws_fetcher.requests.get")
    def test_timeout_kwarg_is_set(self, mock_get):
        mock_get.return_value = _make_response([_station()])
        fetch_weather("C0A980", "KEY")
        _, kwargs = mock_get.call_args
        assert kwargs.get("timeout") == 10

    @patch("pws_fetcher.requests.get")
    def test_high_rainfall_is_parsed_correctly(self, mock_get):
        mock_get.return_value = _make_response([_station(precipitation=42.5)])
        result = fetch_weather("C0A980", "FAKE_KEY")
        assert result["rainfall"] == 42.5


# ---------------------------------------------------------------------------
# format_weather_for_llm
# ---------------------------------------------------------------------------

class TestFormatWeatherForLLM:

    def test_basic_formatting(self):
        weather = {
            "temperature": 25.3,
            "humidity": 70.0,
            "wind_speed": 3.5,
            "rainfall": 0.0,
        }
        out = format_weather_for_llm(weather)
        assert "25.3" in out
        assert "70.0" in out
        assert "3.5" in out
        assert "0.0" in out

    def test_output_contains_units(self):
        weather = {"temperature": 30.0, "humidity": 80.0, "wind_speed": 5.0, "rainfall": 10.0}
        out = format_weather_for_llm(weather)
        assert "°C" in out
        assert "%" in out
        assert "m/s" in out
        assert "mm" in out

    def test_zero_values_are_shown(self):
        weather = {"temperature": 0.0, "humidity": 0.0, "wind_speed": 0.0, "rainfall": 0.0}
        out = format_weather_for_llm(weather)
        assert "0" in out

    def test_output_is_single_line(self):
        weather = {"temperature": 20.0, "humidity": 60.0, "wind_speed": 2.0, "rainfall": 1.0}
        out = format_weather_for_llm(weather)
        assert "\n" not in out
