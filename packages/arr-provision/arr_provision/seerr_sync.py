"""Declarative Jellyseerr/Seerr setup and *arr wiring."""

from __future__ import annotations

import http.cookiejar
import json
import os
import sys
import urllib.request
from typing import Any, Optional

from arr_provision.common import http_json, read_key_file, wait_for_url

DEFAULT_PROFILE = "German 1080p HEVC"
FALLBACK_PROFILE = "English 1080p HEVC"


def _headers(api_key: Optional[str] = None, cookie: Optional[str] = None) -> dict[str, str]:
    hdrs: dict[str, str] = {}
    if api_key:
        hdrs["X-Api-Key"] = api_key
    if cookie:
        hdrs["Cookie"] = cookie
    return hdrs


def _public_status(base_url: str) -> dict[str, Any]:
    status, body = http_json("GET", f"{base_url}/api/v1/settings/public")
    if status >= 400 or not isinstance(body, dict):
        return {}
    return body


def _jellyfin_auth(
    base_url: str,
    cfg: dict[str, Any],
    password: str,
    *,
    setup: bool,
) -> tuple[int, Any, Optional[str]]:
    if setup:
        payload = {
            "username": cfg["adminUsername"],
            "password": password,
            "hostname": cfg["jellyfinHost"],
            "port": int(cfg["jellyfinPort"]),
            "useSsl": cfg.get("jellyfinUseSsl", False),
            "urlBase": cfg.get("jellyfinUrlBase", ""),
            "email": cfg.get("adminEmail", cfg["adminUsername"]),
            "serverType": int(cfg.get("serverType", 2)),
        }
    else:
        payload = {
            "username": cfg["adminUsername"],
            "password": password,
        }

    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    request = urllib.request.Request(
        f"{base_url}/api/v1/auth/jellyfin",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with opener.open(request, timeout=30.0) as response:
            raw = response.read().decode("utf-8")
            body = json.loads(raw) if raw else None
            cookie = None
            for item in jar:
                if item.name == "connect.sid":
                    cookie = f"connect.sid={item.value}"
                    break
            return response.status, body, cookie
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            body = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            body = raw
        return exc.code, body, None


def _initialize_with_jellyfin(base_url: str, cfg: dict[str, Any]) -> Optional[str]:
    password_file = cfg.get("adminPasswordFile", "")
    password = read_key_file(password_file) if password_file else None
    if not password:
        print("Seerr not initialized and no Jellyfin admin password — skipped", file=sys.stderr)
        return None

    status, body, cookie = _jellyfin_auth(base_url, cfg, password, setup=True)
    if status not in (200, 201):
        status, body, cookie = _jellyfin_auth(base_url, cfg, password, setup=False)
    if status not in (200, 201) or not cookie:
        print(f"Seerr Jellyfin auth failed (HTTP {status}): {body}", file=sys.stderr)
        return None

    api_key = read_key_file(cfg.get("apiKeyFile", ""))
    if not api_key:
        print("Seerr Jellyfin auth ok but no API key file — skipped", file=sys.stderr)
        return None

    session_headers = _headers(cookie=cookie)
    libs_status, libraries = http_json(
        "GET",
        f"{base_url}/api/v1/settings/jellyfin/library?sync=true",
        headers=session_headers,
    )
    if libs_status < 400 and isinstance(libraries, list) and libraries:
        ids = ",".join(str(item["id"]) for item in libraries if "id" in item)
        if ids:
            http_json(
                "GET",
                f"{base_url}/api/v1/settings/jellyfin/library?enable={ids}",
                headers=session_headers,
            )

    for endpoint, method in (
        ("/api/v1/settings/jellyfin/sync", "POST"),
        ("/api/v1/settings/initialize", "POST"),
        ("/api/v1/settings/main", "POST"),
    ):
        body_payload = {"locale": cfg.get("locale", "de")} if endpoint.endswith("/main") else None
        init_status, _ = http_json(
            method,
            f"{base_url}{endpoint}",
            headers=session_headers,
            body=body_payload,
        )
        if init_status >= 400:
            print(f"Seerr init step failed: {endpoint} (HTTP {init_status})", file=sys.stderr)

    print("Seerr initialized via Jellyfin")
    return api_key


def _resolve_api_key(base_url: str, cfg: dict[str, Any]) -> Optional[str]:
    public = _public_status(base_url)
    initialized = public.get("initialized", False)
    api_key = read_key_file(cfg.get("apiKeyFile", "")) if cfg.get("apiKeyFile") else None

    if initialized:
        if api_key:
            return api_key
        print("Seerr initialized but no API key file — skipped", file=sys.stderr)
        return None

    return _initialize_with_jellyfin(base_url, cfg)


def _pick_profile(
    test_body: dict[str, Any],
    *,
    preferred: Optional[str] = None,
    fallback: Optional[str] = None,
) -> tuple[Optional[int], Optional[str]]:
    profiles = test_body.get("profiles") or []
    if not profiles:
        return None, None

    by_name = {
        str(item.get("name")): item
        for item in profiles
        if isinstance(item, dict) and item.get("name") is not None
    }
    for name in (preferred, fallback, DEFAULT_PROFILE, FALLBACK_PROFILE):
        if name and name in by_name:
            profile = by_name[name]
            return profile.get("id"), profile.get("name")

    profile = profiles[0]
    return profile.get("id"), profile.get("name")


def _sync_locale(base_url: str, api_key: str, cfg: dict[str, Any]) -> None:
    locale = cfg.get("locale", "de")
    status, main = http_json("GET", f"{base_url}/api/v1/settings/main", headers=_headers(api_key=api_key))
    if status >= 400 or not isinstance(main, dict):
        print(f"Seerr locale: settings/main GET failed (HTTP {status})", file=sys.stderr)
        return
    if main.get("locale") == locale:
        print(f"Seerr locale already {locale}")
        return
    main["locale"] = locale
    put_status, _ = http_json(
        "POST",
        f"{base_url}/api/v1/settings/main",
        headers=_headers(api_key=api_key),
        body=main,
    )
    if put_status < 400:
        print(f"Seerr locale → {locale}")
    else:
        print(f"Seerr locale update failed (HTTP {put_status})", file=sys.stderr)


def _configure_arr(
    base_url: str,
    api_key: str,
    service: str,
    target: dict[str, Any],
) -> None:
    endpoint = f"{base_url}/api/v1/settings/{service}"
    headers = _headers(api_key=api_key)
    test_payload = {
        "hostname": target["host"],
        "port": int(target["port"]),
        "apiKey": read_key_file(target["apiKeyFile"]),
        "useSsl": target.get("useSsl", False),
        "baseUrl": target.get("baseUrl", ""),
    }
    status, test_body = http_json("POST", f"{endpoint}/test", headers=headers, body=test_payload)
    if status >= 400 or not isinstance(test_body, dict):
        print(f"Seerr {service} test failed (HTTP {status})", file=sys.stderr)
        return

    profile_id = target.get("activeProfileId")
    profile_name = target.get("activeProfileName")
    if profile_id is None or not profile_name:
        profile_id, profile_name = _pick_profile(
            test_body,
            preferred=target.get("activeProfileName"),
            fallback=target.get("fallbackProfileName"),
        )
    if profile_id is None or not profile_name:
        print(f"Seerr {service}: no quality profile found", file=sys.stderr)
        return

    server_payload = {
        "name": target.get("name", service.title()),
        "hostname": target["host"],
        "port": int(target["port"]),
        "apiKey": test_payload["apiKey"],
        "useSsl": target.get("useSsl", False),
        "baseUrl": target.get("baseUrl", ""),
        "activeProfileId": int(profile_id),
        "activeProfileName": profile_name,
        "activeDirectory": target.get("activeDirectory", ""),
        "isDefault": target.get("isDefault", True),
        "is4k": target.get("is4k", False),
        "syncEnabled": target.get("syncEnabled", True),
        "preventSearch": target.get("preventSearch", False),
    }
    if service == "sonarr":
        server_payload["enableSeasonFolders"] = target.get("enableSeasonFolders", True)
        server_payload["seriesType"] = target.get("seriesType", "standard")
        server_payload["animeSeriesType"] = target.get("animeSeriesType", "anime")
        server_payload["activeAnimeDirectory"] = target.get(
            "activeAnimeDirectory", server_payload["activeDirectory"]
        )
        server_payload["activeAnimeProfileId"] = int(profile_id)
        server_payload["activeAnimeProfileName"] = profile_name
    if service == "radarr":
        server_payload["minimumAvailability"] = target.get("minimumAvailability", "released")

    status, existing = http_json("GET", endpoint, headers=headers)
    existing_id = None
    if status < 400 and isinstance(existing, list):
        existing_id = next(
            (item.get("id") for item in existing if item.get("name") == server_payload["name"]),
            None,
        )

    if existing_id is not None:
        status, resp = http_json("PUT", f"{endpoint}/{existing_id}", headers=headers, body=server_payload)
        action = "updated"
    else:
        status, resp = http_json("POST", endpoint, headers=headers, body=server_payload)
        action = "created"

    if status in (200, 201, 204):
        print(f"Seerr {service}: {action} ({server_payload['name']}, profile {profile_name})")
    else:
        print(f"Seerr {service}: failed to {action} (HTTP {status}): {resp}", file=sys.stderr)


def sync_seerr() -> int:
    host = os.environ.get("SEERR_HOST", "127.0.0.1")
    port = int(os.environ.get("SEERR_PORT", "5002"))
    base_url = f"http://{host}:{port}"
    cfg = json.loads(os.environ["SEERR_CONFIG_JSON"])

    if not wait_for_url(f"{base_url}/api/v1/status"):
        print("Seerr not reachable — skipped", file=sys.stderr)
        return 0

    api_key = _resolve_api_key(base_url, cfg)
    if not api_key:
        return 0

    _sync_locale(base_url, api_key, cfg)

    for service in ("sonarr", "radarr"):
        target = cfg.get(service)
        if target and target.get("enabled"):
            _configure_arr(base_url, api_key, service, target)

    print("Seerr sync complete.")
    return 0


def main() -> None:
    raise SystemExit(sync_seerr())


if __name__ == "__main__":
    main()
