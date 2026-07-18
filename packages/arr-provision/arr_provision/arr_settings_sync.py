"""TRaSH-related Radarr/Sonarr host settings (language Any, repacks doNotPrefer)."""

from __future__ import annotations

import os
import sys
from typing import Any

from arr_provision.common import arr_api_base, http_json, read_key_file


def _headers(api_key: str) -> dict[str, str]:
    return {"X-Api-Key": api_key}


def _set_repacks_do_not_prefer(base: str, api_key: str, label: str) -> None:
    status, body = http_json("GET", f"{base}/config/mediamanagement", headers=_headers(api_key))
    if status >= 400 or not isinstance(body, dict):
        print(f"{label}: mediamanagement GET failed (HTTP {status})", file=sys.stderr)
        return
    if body.get("downloadPropersAndRepacks") == "doNotPrefer":
        print(f"{label}: downloadPropersAndRepacks already doNotPrefer")
        return
    body["downloadPropersAndRepacks"] = "doNotPrefer"
    status, _ = http_json(
        "PUT",
        f"{base}/config/mediamanagement",
        headers=_headers(api_key),
        body=body,
    )
    if status < 400:
        print(f"{label}: downloadPropersAndRepacks → doNotPrefer")
    else:
        print(f"{label}: mediamanagement PUT failed (HTTP {status})", file=sys.stderr)


def _ensure_root_folder(base: str, api_key: str, path: str, label: str) -> None:
    if not path:
        return
    status, folders = http_json("GET", f"{base}/rootfolder", headers=_headers(api_key))
    if status >= 400 or not isinstance(folders, list):
        print(f"{label}: rootfolder GET failed (HTTP {status})", file=sys.stderr)
        return
    if any(isinstance(item, dict) and item.get("path") == path for item in folders):
        print(f"{label}: root folder already exists ({path})")
        return
    status, body = http_json(
        "POST",
        f"{base}/rootfolder",
        headers=_headers(api_key),
        body={"path": path},
    )
    if status in (200, 201):
        print(f"{label}: root folder created ({path})")
    else:
        print(f"{label}: root folder POST failed (HTTP {status}): {body}", file=sys.stderr)


def _set_profiles_language_any(base: str, api_key: str, label: str) -> None:
    status, profiles = http_json("GET", f"{base}/qualityprofile", headers=_headers(api_key))
    if status >= 400 or not isinstance(profiles, list):
        print(f"{label}: qualityprofile GET failed (HTTP {status})", file=sys.stderr)
        return
    for profile in profiles:
        if not isinstance(profile, dict):
            continue
        language = profile.get("language") or {}
        if language.get("name") == "Any":
            continue
        profile["language"] = {"id": 0, "name": "Any"}
        pid = profile.get("id")
        if pid is None:
            continue
        put_status, _ = http_json(
            "PUT",
            f"{base}/qualityprofile/{pid}",
            headers=_headers(api_key),
            body=profile,
        )
        if put_status < 400:
            print(f"{label}: profile '{profile.get('name')}' language → Any")
        else:
            print(
                f"{label}: profile '{profile.get('name')}' language update failed (HTTP {put_status})",
                file=sys.stderr,
            )


def _sync_app(
    host: str,
    port: int,
    api_key_file: str,
    label: str,
    *,
    root_folder: str = "",
) -> None:
    api_key = read_key_file(api_key_file)
    if not api_key:
        print(f"{label}: no API key — skipped", file=sys.stderr)
        return
    base = arr_api_base(host, port, "v3")
    _ensure_root_folder(base, api_key, root_folder, label)
    _set_repacks_do_not_prefer(base, api_key, label)
    _set_profiles_language_any(base, api_key, label)


def sync_arr_settings() -> int:
    host = os.environ.get("ARR_HOST", "127.0.0.1")

    if os.environ.get("SYNC_RADARR", "0") == "1":
        _sync_app(
            host,
            int(os.environ["RADARR_PORT"]),
            os.environ["RADARR_KEY_FILE"],
            "Radarr",
            root_folder=os.environ.get("RADARR_ROOT_FOLDER", ""),
        )

    if os.environ.get("SYNC_SONARR", "0") == "1":
        _sync_app(
            host,
            int(os.environ["SONARR_PORT"]),
            os.environ["SONARR_KEY_FILE"],
            "Sonarr",
            root_folder=os.environ.get("SONARR_ROOT_FOLDER", ""),
        )

    print("Arr settings sync complete.")
    return 0


def main() -> None:
    raise SystemExit(sync_arr_settings())


if __name__ == "__main__":
    main()
