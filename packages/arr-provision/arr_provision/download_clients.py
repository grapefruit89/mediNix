"""Register SABnzbd as download client in *arr services."""

from __future__ import annotations

import json
import os
import sys

from arr_provision.common import arr_api_base, http_json, read_key_file, title_case_service, wait_for_url


def _payload(sab_host: str, sab_port: int, sab_key: str, category: str) -> dict:
    return {
        "enable": True,
        "name": "SABnzbd",
        "protocol": "usenet",
        "priority": 1,
        "implementationName": "SABnzbd",
        "implementation": "Sabnzbd",
        "configContract": "SabnzbdSettings",
        "fields": [
            {"name": "host", "value": sab_host},
            {"name": "port", "value": sab_port},
            {"name": "useSsl", "value": False},
            {"name": "apiKey", "value": sab_key},
            {"name": "category", "value": category},
        ],
    }


def sync_download_clients() -> int:
    sab_host = os.environ.get("SAB_HOST", "127.0.0.1")
    sab_port = int(os.environ.get("SAB_PORT", "5007"))
    sab_key_file = os.environ["SAB_KEY_FILE"]
    host_bridge = os.environ.get("HOST_BRIDGE", "127.0.0.1")
    targets = json.loads(os.environ["TARGETS_JSON"])

    sab_key = read_key_file(sab_key_file)
    if not sab_key:
        print(f"SABnzbd API key missing: {sab_key_file} — skipped", file=sys.stderr)
        return 0

    sab_url = f"http://{sab_host}:{sab_port}/api?apikey={sab_key}&mode=version"
    if not wait_for_url(sab_url, max_attempts=30):
        print("SABnzbd not reachable — skipped", file=sys.stderr)
        return 0

    for target in targets:
        name = target["name"]
        impl = title_case_service(name)
        api_key_file = target["apiKeyFile"]
        api_key = read_key_file(api_key_file)
        if not api_key:
            print(f"{impl}: API key missing ({api_key_file}) — skipped")
            continue

        base = arr_api_base(host_bridge, int(target["port"]), target["apiVersion"])
        headers = {"X-Api-Key": api_key}
        if not wait_for_url(f"{base}/system/status", headers=headers, max_attempts=15):
            print(f"{impl}: not reachable — skipped")
            continue

        status, clients = http_json("GET", f"{base}/downloadclient", headers=headers)
        if status >= 400:
            print(f"{impl}: failed to list download clients (HTTP {status})", file=sys.stderr)
            continue

        existing = next((c.get("id") for c in clients or [] if c.get("implementation") == "Sabnzbd"), None)
        if existing:
            print(f"{impl}: SABnzbd already registered (ID: {existing})")
            continue

        status, _ = http_json(
            "POST",
            f"{base}/downloadclient",
            headers=headers,
            body=_payload(sab_host, sab_port, sab_key, target["category"]),
        )
        if status in (200, 201):
            print(f"{impl}: SABnzbd registered (category: {target['category']})")
        else:
            print(f"{impl}: failed to register SABnzbd (HTTP {status})", file=sys.stderr)

    print("Download-client sync complete.")
    return 0


def main() -> None:
    raise SystemExit(sync_download_clients())


if __name__ == "__main__":
    main()