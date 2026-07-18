"""Declarative Prowlarr indexer and application registration."""

from __future__ import annotations

import json
import os
import sqlite3
import sys

from arr_provision.common import http_json, read_key_file, title_case_service, wait_for_url

_VPN_DISABLED_TASKS = (
    "NzbDrone.Core.Update.Commands.ApplicationUpdateCheckCommand",
    "NzbDrone.Core.IndexerVersions.IndexerDefinitionUpdateCommand",
)
# Minutes — ~1 year; Prowlarr API erlaubt kein Task-PUT, DB-Interval ist der Weg.
_VPN_DISABLED_INTERVAL_MIN = 525600


def _register_indexer(api: str, headers: dict, indexer: dict) -> None:
    name = indexer["name"]
    status, current = http_json("GET", f"{api}/indexer", headers=headers)
    if status >= 400:
        print(f"Indexer {name}: failed to list indexers (HTTP {status})", file=sys.stderr)
        return

    if any(item.get("name") == name for item in current or []):
        print(f"Indexer {name}: already present")
        return

    api_key = ""
    key_file = indexer.get("apiKeyFile") or ""
    if key_file:
        api_key = read_key_file(key_file) or ""

    payload = {
        "name": name,
        "enable": True,
        "protocol": indexer.get("protocol", "usenet"),
        "implementation": indexer.get("implementation", "Newznab"),
        "configContract": indexer.get("configContract", "NewznabSettings"),
        "fields": [
            {"name": "baseUrl", "value": indexer["baseUrl"]},
            {"name": "apiKey", "value": api_key},
        ],
    }
    status, _ = http_json("POST", f"{api}/indexer", headers=headers, body=payload)
    if status in (200, 201):
        print(f"Indexer {name}: registered")
    else:
        print(f"Indexer {name}: registration failed (HTTP {status})", file=sys.stderr)


def _register_application(api: str, headers: dict, app: dict, sync_level: str) -> None:
    name = app["name"]
    impl = title_case_service(name)
    status, current = http_json("GET", f"{api}/applications", headers=headers)
    if status >= 400:
        print(f"Application {impl}: failed to list apps (HTTP {status})", file=sys.stderr)
        return

    if any(item.get("name") == impl for item in current or []):
        print(f"Application {impl}: already present")
        return

    api_key = read_key_file(app["apiKeyFile"])
    if not api_key:
        print(f"Application {impl}: API key missing — skipped")
        return

    payload = {
        "name": impl,
        "enable": True,
        "implementation": impl,
        "implementationName": impl,
        "configContract": f"{impl}Settings",
        "syncLevel": sync_level,
        "fields": [
            {"name": "prowlarrUrl", "value": api},
            {"name": "baseUrl", "value": f"http://{app['host']}:{app['port']}"},
            {"name": "apiKey", "value": api_key},
        ],
    }
    status, _ = http_json("POST", f"{api}/applications", headers=headers, body=payload)
    if status in (200, 201):
        print(f"Application {impl}: registered")
    else:
        print(f"Application {impl}: registration failed (HTTP {status})", file=sys.stderr)


def _trigger_application_sync(api: str, headers: dict) -> None:
    status, _ = http_json(
        "POST",
        f"{api}/command",
        headers=headers,
        body={"name": "ApplicationsSync"},
    )
    if status in (200, 201):
        print("Prowlarr application sync command sent")
    else:
        print(f"Prowlarr application sync command failed (HTTP {status})", file=sys.stderr)


def _tune_vpn_sandbox(api_v1: str, headers: dict) -> None:
    status, host_cfg = http_json("GET", f"{api_v1}/config/host", headers=headers)
    if status >= 400 or not isinstance(host_cfg, dict):
        print(f"Prowlarr host config GET failed (HTTP {status})", file=sys.stderr)
    elif host_cfg.get("updateMechanism") != "external" or host_cfg.get("updateAutomatically"):
        host_cfg["updateMechanism"] = "external"
        host_cfg["updateAutomatically"] = False
        put_status, _ = http_json("PUT", f"{api_v1}/config/host", headers=headers, body=host_cfg)
        if put_status < 400:
            print("Prowlarr: updateMechanism → external (VPN sandbox)")
        else:
            print(f"Prowlarr host config PUT failed (HTTP {put_status})", file=sys.stderr)

    db_path = os.environ.get("PROWLARR_DB", "/var/lib/prowlarr/prowlarr.db")
    try:
        con = sqlite3.connect(db_path)
        for type_name in _VPN_DISABLED_TASKS:
            cur = con.execute(
                "UPDATE ScheduledTasks SET Interval = ? WHERE TypeName = ? AND Interval < ?",
                (_VPN_DISABLED_INTERVAL_MIN, type_name, _VPN_DISABLED_INTERVAL_MIN),
            )
            if cur.rowcount:
                short = type_name.rsplit(".", maxsplit=1)[-1]
                print(f"Prowlarr: stretched scheduled task interval ({short})")
        con.commit()
        con.close()
    except OSError as exc:
        print(f"Prowlarr DB tune skipped: {exc}", file=sys.stderr)


def _register_backup_indexer(app: dict, backup: dict) -> None:
    from arr_provision.common import arr_api_base, title_case_service

    name = app["name"]
    impl = title_case_service(name)
    api_key = read_key_file(app["apiKeyFile"])
    if not api_key:
        print(f"{impl}: API key missing — backup indexer skipped")
        return

    base = arr_api_base(app["host"], int(app["port"]), app["apiVersion"])
    headers = {"X-Api-Key": api_key}
    if not wait_for_url(f"{base}/system/status", headers=headers, max_attempts=5):
        print(f"{impl}: not reachable — backup indexer skipped")
        return

    status, current = http_json("GET", f"{base}/indexer", headers=headers)
    if status >= 400:
        print(f"{impl}: failed to list indexers (HTTP {status})", file=sys.stderr)
        return

    bidx_name = backup["name"]
    if any(item.get("name") == bidx_name for item in current or []):
        print(f"{impl}: backup indexer {bidx_name} already present")
        return

    key_file = backup.get("apiKeyFile") or ""
    bidx_key = read_key_file(key_file) if key_file else ""
    payload = {
        "name": bidx_name,
        "enable": False,
        "protocol": "usenet",
        "priority": 50,
        "supportsRss": True,
        "supportsSearch": True,
        "implementation": "Newznab",
        "implementationName": "Newznab",
        "configContract": "NewznabSettings",
        "fields": [
            {"name": "baseUrl", "value": backup["baseUrl"]},
            {"name": "apiKey", "value": bidx_key},
            {"name": "categories", "value": backup.get("categories", [])},
        ],
    }
    status, _ = http_json("POST", f"{base}/indexer", headers=headers, body=payload)
    if status in (200, 201):
        print(f"{impl}: backup indexer {bidx_name} registered (disabled)")
    else:
        print(f"{impl}: backup indexer {bidx_name} failed (HTTP {status})", file=sys.stderr)


def sync_prowlarr() -> int:
    host = os.environ.get("PROWLARR_HOST", "127.0.0.1")
    port = int(os.environ.get("PROWLARR_PORT", "5006"))
    key_file = os.environ["PROWLARR_KEY_FILE"]
    sync_level = os.environ.get("SYNC_LEVEL", "fullSync")
    indexers = json.loads(os.environ.get("INDEXERS_JSON", "[]"))
    apps = json.loads(os.environ.get("APPS_JSON", "[]"))
    backup_indexers = json.loads(os.environ.get("BACKUP_INDEXERS_JSON", "[]"))

    api_key = read_key_file(key_file)
    if not api_key:
        print(f"Prowlarr API key missing: {key_file} — skipped", file=sys.stderr)
        return 0

    api = f"http://{host}:{port}"
    headers = {"X-Api-Key": api_key}
    if not wait_for_url(f"{api}/api/v1/system/status", headers=headers):
        print("Prowlarr not reachable — skipped", file=sys.stderr)
        return 0

    api_v1 = f"{api}/api/v1"

    if os.environ.get("PROWLARR_VPN_SANDBOX", "0") == "1":
        print("=== Prowlarr: VPN sandbox tuning ===")
        _tune_vpn_sandbox(api_v1, headers)

    print("=== Prowlarr: indexer registration ===")
    for indexer in indexers:
        _register_indexer(api_v1, headers, indexer)

    print("=== Prowlarr: application registration ===")
    for app in apps:
        _register_application(api_v1, headers, app, sync_level)

    print("=== Prowlarr: trigger application sync ===")
    _trigger_application_sync(api_v1, headers)

    if backup_indexers:
        print("=== Backup indexers in *arr apps (disabled) ===")
        for backup in backup_indexers:
            targets = backup.get("targetApps") or []
            for app in apps:
                if targets and app["name"] not in targets:
                    continue
                _register_backup_indexer(app, backup)

    print("Prowlarr sync complete.")
    return 0


def main() -> None:
    raise SystemExit(sync_prowlarr())


if __name__ == "__main__":
    main()