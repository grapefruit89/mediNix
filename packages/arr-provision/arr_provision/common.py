"""Shared helpers for HTTP API provisioning.

=============================================================================
PRIMAERQUELLEN -- NICHT ENTFERNEN
=============================================================================
Diese URLs sind Teil der Architektur, kein Kommentar-Ballast. Wer sie loescht,
zwingt den naechsten Bearbeiter zum Raten.

  Radarr   OpenAPI : https://raw.githubusercontent.com/Radarr/Radarr/develop/src/Radarr.Api.V3/openapi.json
  Radarr   Doku    : https://radarr.video/docs/api/
  Sonarr   OpenAPI : https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V3/openapi.json
  Sonarr   Doku    : https://sonarr.tv/docs/api/#v3
  Prowlarr OpenAPI : https://raw.githubusercontent.com/Prowlarr/Prowlarr/develop/src/Prowlarr.Api.V1/openapi.json
  Prowlarr Doku    : https://prowlarr.com/docs/api/
  Lidarr / Readarr : gleiche Struktur, Api.V1

AUTORITATIV ist aber die LAUFENDE INSTANZ, nicht der develop-Branch:
  curl -s -H "X-Api-Key: $KEY" http://127.0.0.1:<port>/api/<v>/system/status

API-Versionen:  Sonarr/Radarr = v3 | Prowlarr/Lidarr/Readarr = v1
Auth:           Header X-Api-Key

Endpunkt-Inventar + Verifikationsstand: ../../docs/api-reference.md
Regeln fuer Agenten:                    ../../AGENTS.md  (Regel 0)
=============================================================================
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Mapping, MutableMapping, Optional


def read_key_file(path: str) -> Optional[str]:
    try:
        with open(path, encoding="utf-8") as handle:
            value = handle.read().strip()
            return value or None
    except OSError:
        return None


def wait_for_url(
    url: str,
    *,
    headers: Optional[Mapping[str, str]] = None,
    max_attempts: int = 30,
    sleep_seconds: float = 2.0,
    require_fail: bool = False,
    timeout: float = 5.0,
) -> bool:
    hdrs = dict(headers or {})
    for attempt in range(1, max_attempts + 1):
        try:
            request = urllib.request.Request(url, headers=hdrs)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                if require_fail and response.status >= 400:
                    raise urllib.error.HTTPError(url, response.status, "", hdrs, None)
            print(f"Service available at {url} (attempt {attempt})")
            return True
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            if attempt == max_attempts:
                print(f"Service not available at {url} after {max_attempts} attempts: {exc}", file=sys.stderr)
                return False
            time.sleep(sleep_seconds)
    return False


def http_json(
    method: str,
    url: str,
    *,
    headers: Optional[MutableMapping[str, str]] = None,
    body: Any = None,
    timeout: float = 30.0,
) -> tuple[int, Any]:
    payload = None
    hdrs: MutableMapping[str, str] = {"Accept": "application/json"}
    if headers:
        hdrs.update(headers)
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    request = urllib.request.Request(url, data=payload, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return exc.code, parsed


def arr_api_base(host: str, port: int, api_version: str) -> str:
    return f"http://{host}:{port}/api/{api_version}"


def title_case_service(name: str) -> str:
    return name[:1].upper() + name[1:] if name else name