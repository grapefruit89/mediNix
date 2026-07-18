"""Assign existing Radarr/Sonarr library items to German/English 1080p HEVC profiles."""

from __future__ import annotations

import os
import sys
from typing import Any, Optional

from arr_provision.common import arr_api_base, http_json, read_key_file, title_case_service

GERMAN_PROFILE = "German 1080p HEVC"
ENGLISH_PROFILE = "English 1080p HEVC"
_GERMAN_LANGS = frozenset({"German", "de", "Deutsch"})


def _headers(api_key: str) -> dict[str, str]:
    return {"X-Api-Key": api_key}


def _profile_ids(base: str, api_key: str) -> dict[str, int]:
    status, profiles = http_json("GET", f"{base}/qualityprofile", headers=_headers(api_key))
    if status >= 400 or not isinstance(profiles, list):
        return {}
    result: dict[str, int] = {}
    for profile in profiles:
        if isinstance(profile, dict) and profile.get("name") and profile.get("id") is not None:
            result[str(profile["name"])] = int(profile["id"])
    return result


def _pick_profile_id(lang_name: Optional[str], profile_ids: dict[str, int]) -> Optional[int]:
    german_id = profile_ids.get(GERMAN_PROFILE)
    english_id = profile_ids.get(ENGLISH_PROFILE)
    if german_id is None and english_id is None:
        return None
    if lang_name in _GERMAN_LANGS:
        return german_id or english_id
    return english_id or german_id


def _sync_sonarr(host: str, port: int, key_file: str) -> None:
    label = title_case_service("sonarr")
    api_key = read_key_file(key_file)
    if not api_key:
        print(f"{label}: no API key — skipped", file=sys.stderr)
        return

    base = arr_api_base(host, port, "v3")
    profile_ids = _profile_ids(base, api_key)
    if GERMAN_PROFILE not in profile_ids and ENGLISH_PROFILE not in profile_ids:
        print(f"{label}: TRaSH profiles missing — run recyclarr first", file=sys.stderr)
        return

    status, series_list = http_json("GET", f"{base}/series", headers=_headers(api_key))
    if status >= 400 or not isinstance(series_list, list):
        print(f"{label}: series GET failed (HTTP {status})", file=sys.stderr)
        return

    updated = 0
    for series in series_list:
        if not isinstance(series, dict):
            continue
        lang = (series.get("originalLanguage") or {}).get("name")
        target_id = _pick_profile_id(lang, profile_ids)
        if target_id is None or series.get("qualityProfileId") == target_id:
            continue
        series["qualityProfileId"] = target_id
        put_status, _ = http_json(
            "PUT",
            f"{base}/series/{series['id']}",
            headers=_headers(api_key),
            body=series,
        )
        if put_status < 400:
            updated += 1

    print(f"{label}: assigned TRaSH profiles to {updated}/{len(series_list)} series")


def _sync_radarr(host: str, port: int, key_file: str) -> None:
    label = title_case_service("radarr")
    api_key = read_key_file(key_file)
    if not api_key:
        print(f"{label}: no API key — skipped", file=sys.stderr)
        return

    base = arr_api_base(host, port, "v3")
    profile_ids = _profile_ids(base, api_key)
    if GERMAN_PROFILE not in profile_ids and ENGLISH_PROFILE not in profile_ids:
        print(f"{label}: TRaSH profiles missing — run recyclarr first", file=sys.stderr)
        return

    status, movies = http_json("GET", f"{base}/movie", headers=_headers(api_key))
    if status >= 400 or not isinstance(movies, list):
        print(f"{label}: movie GET failed (HTTP {status})", file=sys.stderr)
        return

    updated = 0
    for movie in movies:
        if not isinstance(movie, dict):
            continue
        lang = (movie.get("originalLanguage") or {}).get("name")
        target_id = _pick_profile_id(lang, profile_ids)
        if target_id is None or movie.get("qualityProfileId") == target_id:
            continue
        movie["qualityProfileId"] = target_id
        put_status, _ = http_json(
            "PUT",
            f"{base}/movie/{movie['id']}",
            headers=_headers(api_key),
            body=movie,
        )
        if put_status < 400:
            updated += 1

    print(f"{label}: assigned TRaSH profiles to {updated}/{len(movies)} movies")


def sync_profiles() -> int:
    host = os.environ.get("ARR_HOST", "127.0.0.1")

    if os.environ.get("SYNC_SONARR", "0") == "1":
        _sync_sonarr(host, int(os.environ["SONARR_PORT"]), os.environ["SONARR_KEY_FILE"])
    if os.environ.get("SYNC_RADARR", "0") == "1":
        _sync_radarr(host, int(os.environ["RADARR_PORT"]), os.environ["RADARR_KEY_FILE"])

    print("Profile sync complete.")
    return 0


def main() -> None:
    raise SystemExit(sync_profiles())


if __name__ == "__main__":
    main()
