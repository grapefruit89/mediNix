"""Declarative Jellyfin bootstrap: admin, libraries, library options, users, intro scan."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

from arr_provision.common import http_json, read_key_file, wait_for_url

_EMBY_AUTH = (
    'MediaBrowser Client="arr-provision", Device="q958", DeviceId="q958-arr-provision", Version="1.0.0"'
)

_DECLARED_LIBRARIES = ("Filme", "Serien")
_MEDIA_SEGMENT_TASK_KEY = "TaskExtractMediaSegments"


def _jellyfin_base() -> Optional[str]:
    host = os.environ.get("JELLYFIN_HOST", "127.0.0.1")
    port_str = os.environ.get("JELLYFIN_PORT")
    if not port_str:
        print("JELLYFIN_PORT not set — skipped", file=sys.stderr)
        return None
    return f"http://{host}:{port_str}"


def _auth_headers(token: str) -> dict[str, str]:
    return {"X-Emby-Authorization": f'{_EMBY_AUTH}, Token="{token}"'}


def _public_info(base_url: str) -> dict[str, Any]:
    status, body = http_json("GET", f"{base_url}/System/Info/Public")
    if status >= 400 or not isinstance(body, dict):
        return {}
    return body


def _authenticate(base_url: str, username: str, password: str) -> Optional[tuple[str, str]]:
    payload = {"Username": username, "Pw": password}
    request = urllib.request.Request(
        f"{base_url}/Users/authenticatebyname",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Emby-Authorization": _EMBY_AUTH,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30.0) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print(f"Jellyfin auth failed for {username} (HTTP {exc.code})", file=sys.stderr)
        return None

    token = body.get("AccessToken")
    user = body.get("User") or {}
    user_id = user.get("Id")
    if not token or not user_id:
        return None
    return token, user_id


def _set_password(
    base_url: str,
    user_id: str,
    token: str,
    new_password: str,
    *,
    current_password: Optional[str] = None,
) -> bool:
    payload: dict[str, Any] = {"Id": user_id, "NewPw": new_password}
    if current_password:
        payload["CurrentPw"] = current_password
    status, body = http_json(
        "POST",
        f"{base_url}/Users/{user_id}/Password",
        headers={**_auth_headers(token), "Content-Type": "application/json"},
        body=payload,
    )
    if status >= 400:
        print(f"Jellyfin password update failed (HTTP {status}): {body}", file=sys.stderr)
        return False
    return True


def _complete_startup(base_url: str, username: str, password: str) -> bool:
    payload = {"Name": username, "Password": password, "PasswordConfirm": password}
    request = urllib.request.Request(
        f"{base_url}/Startup/User",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30.0) as response:
            if response.status not in (200, 204):
                print(f"Jellyfin startup user failed (HTTP {response.status})", file=sys.stderr)
                return False
    except urllib.error.HTTPError as exc:
        print(f"Jellyfin startup user failed (HTTP {exc.code})", file=sys.stderr)
        return False

    status, _ = http_json("POST", f"{base_url}/Startup/Complete", body={})
    if status >= 400:
        print(f"Jellyfin startup complete failed (HTTP {status})", file=sys.stderr)
        return False
    print(f"Jellyfin startup wizard completed (user: {username})")
    return True


def _library_has_path(library: dict[str, Any], path: str) -> bool:
    return path in (library.get("Locations") or [])


def _list_libraries(base_url: str, token: str) -> list[dict[str, Any]]:
    status, body = http_json(
        "GET",
        f"{base_url}/Library/VirtualFolders",
        headers=_auth_headers(token),
    )
    if status >= 400 or not isinstance(body, list):
        print(f"Jellyfin libraries GET failed (HTTP {status})", file=sys.stderr)
        return []
    return [item for item in body if isinstance(item, dict)]


def _prune_undeclared_libraries(base_url: str, token: str) -> None:
    for library in _list_libraries(base_url, token):
        name = library.get("Name")
        if not name or name in _DECLARED_LIBRARIES:
            continue
        query = urllib.parse.urlencode({"name": name, "refreshLibrary": "false"})
        request = urllib.request.Request(
            f"{base_url}/Library/VirtualFolders?{query}",
            headers=_auth_headers(token),
            method="DELETE",
        )
        try:
            with urllib.request.urlopen(request, timeout=30.0) as response:
                if response.status in (200, 204):
                    print(f"Jellyfin removed undeclared library ({name})")
        except urllib.error.HTTPError as exc:
            print(f"Jellyfin library remove failed ({name}, HTTP {exc.code})", file=sys.stderr)


def _ensure_libraries(base_url: str, token: str) -> None:
    libraries = [
        ("Filme", "movies", os.environ.get("JELLYFIN_MOVIES_PATH", "")),
        ("Serien", "tvshows", os.environ.get("JELLYFIN_TV_PATH", "")),
    ]
    desired = [(name, collection_type, path) for name, collection_type, path in libraries if path]
    if not desired:
        return

    existing = _list_libraries(base_url, token)

    for name, collection_type, path in desired:
        match = next((item for item in existing if item.get("Name") == name), None)
        if isinstance(match, dict) and _library_has_path(match, path):
            print(f"Jellyfin library already configured ({name} → {path})")
            continue

        if isinstance(match, dict):
            add_status, add_body = http_json(
                "POST",
                f"{base_url}/Library/VirtualFolders/Paths",
                headers=_auth_headers(token),
                body={"Name": name, "Path": path},
            )
            if add_status in (200, 204):
                print(f"Jellyfin library path added ({name} → {path})")
            else:
                print(
                    f"Jellyfin library path add failed ({name}, HTTP {add_status}): {add_body}",
                    file=sys.stderr,
                )
            continue

        query = urllib.parse.urlencode(
            {
                "name": name,
                "collectionType": collection_type,
                "refreshLibrary": "false",
                "paths": path,
            }
        )
        request = urllib.request.Request(
            f"{base_url}/Library/VirtualFolders?{query}",
            headers=_auth_headers(token),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=30.0) as response:
                if response.status in (200, 204):
                    print(f"Jellyfin library created ({name} → {path})")
                else:
                    print(f"Jellyfin library create failed ({name}, HTTP {response.status})", file=sys.stderr)
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            print(f"Jellyfin library create failed ({name}, HTTP {exc.code}): {raw}", file=sys.stderr)


def _configure_library_options(base_url: str, token: str) -> None:
    refresh_days = int(os.environ.get("JELLYFIN_LIBRARY_REFRESH_DAYS", "1"))
    enable_chapters = os.environ.get("JELLYFIN_ENABLE_CHAPTER_EXTRACTION", "1") == "1"
    metadata_lang = os.environ.get("JELLYFIN_METADATA_LANGUAGE", "")
    metadata_country = os.environ.get("JELLYFIN_METADATA_COUNTRY", "")

    for library in _list_libraries(base_url, token):
        name = library.get("Name")
        if name not in _DECLARED_LIBRARIES:
            continue
        item_id = library.get("ItemId")
        options = library.get("LibraryOptions")
        if not item_id or not isinstance(options, dict):
            continue

        options = dict(options)
        options["EnableChapterImageExtraction"] = enable_chapters
        options["ExtractChapterImagesDuringLibraryScan"] = enable_chapters
        options["AutomaticRefreshIntervalDays"] = refresh_days
        if metadata_lang:
            options["PreferredMetadataLanguage"] = metadata_lang
        if metadata_country:
            options["MetadataCountryCode"] = metadata_country

        status, body = http_json(
            "POST",
            f"{base_url}/Library/VirtualFolders/LibraryOptions",
            headers={**_auth_headers(token), "Content-Type": "application/json"},
            body={"Id": item_id, "LibraryOptions": options},
        )
        if status in (200, 204):
            print(
                f"Jellyfin library options synced ({name}: refresh={refresh_days}d, chapters={enable_chapters})"
            )
        else:
            print(f"Jellyfin library options failed ({name}, HTTP {status}): {body}", file=sys.stderr)


def _trigger_scheduled_task(base_url: str, token: str, task_key: str, label: str) -> None:
    status, tasks = http_json("GET", f"{base_url}/ScheduledTasks", headers=_auth_headers(token))
    if status >= 400 or not isinstance(tasks, list):
        print(f"Jellyfin scheduled tasks GET failed (HTTP {status})", file=sys.stderr)
        return
    task = next(
        (
            t
            for t in tasks
            if isinstance(t, dict)
            and (t.get("Key") == task_key or (t.get("LastExecutionResult") or {}).get("Key") == task_key)
        ),
        None,
    )
    if not isinstance(task, dict):
        print(f"Jellyfin scheduled task not found ({label})", file=sys.stderr)
        return
    task_id = task.get("Id")
    if not task_id:
        return
    if task.get("State") == "Running":
        print(f"Jellyfin scheduled task already running ({label})")
        return
    run_status, run_body = http_json(
        "POST",
        f"{base_url}/ScheduledTasks/Running/{task_id}",
        headers=_auth_headers(token),
        body={},
    )
    if run_status in (200, 204):
        print(f"Jellyfin scheduled task triggered ({label})")
    else:
        print(f"Jellyfin scheduled task trigger failed ({label}, HTTP {run_status}): {run_body}", file=sys.stderr)


def _ensure_intro_pipeline(base_url: str, token: str) -> None:
    if os.environ.get("JELLYFIN_ENABLE_INTRO_SCAN", "1") != "1":
        return
    _trigger_scheduled_task(base_url, token, "RefreshChapterImages", "Extract Chapter Images")
    _trigger_scheduled_task(base_url, token, _MEDIA_SEGMENT_TASK_KEY, "Media Segment Scan")


def _ensure_extra_users(base_url: str, token: str) -> None:
    raw = os.environ.get("JELLYFIN_EXTRA_USERS_JSON", "").strip()
    if not raw:
        return
    try:
        users = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"JELLYFIN_EXTRA_USERS_JSON invalid: {exc}", file=sys.stderr)
        return
    if not isinstance(users, list):
        print("JELLYFIN_EXTRA_USERS_JSON must be a list", file=sys.stderr)
        return

    status, existing = http_json("GET", f"{base_url}/Users", headers=_auth_headers(token))
    existing_names = set()
    if status < 400 and isinstance(existing, list):
        existing_names = {u.get("Name") for u in existing if isinstance(u, dict) and u.get("Name")}

    for entry in users:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name") or entry.get("Name")
        password_file = entry.get("password_file") or entry.get("passwordFile")
        if not name or not password_file:
            continue
        if name in existing_names:
            print(f"Jellyfin user already exists ({name})")
            continue
        password = read_key_file(password_file)

        if not password:
            print(f"Jellyfin user password missing ({name})", file=sys.stderr)
            continue
        create_status, create_body = http_json(
            "POST",
            f"{base_url}/Users/New",
            headers={**_auth_headers(token), "Content-Type": "application/json"},
            body={"Name": name, "Password": password},
        )
        if create_status in (200, 201, 204):
            print(f"Jellyfin user created ({name})")
        else:
            print(f"Jellyfin user create failed ({name}, HTTP {create_status}): {create_body}", file=sys.stderr)


def _post_auth_setup(base_url: str, token: str) -> None:
    _prune_undeclared_libraries(base_url, token)
    _ensure_libraries(base_url, token)
    _configure_library_options(base_url, token)
    _ensure_extra_users(base_url, token)
    _ensure_intro_pipeline(base_url, token)


def setup_jellyfin() -> int:
    base_url = _jellyfin_base()
    if base_url is None:
        return 0
    username = os.environ.get("JELLYFIN_ADMIN_USER", "admin")
    password_file = os.environ.get("JELLYFIN_ADMIN_PASSWORD_FILE", "/var/lib/secrets/jellyfin_admin_password")

    if not wait_for_url(f"{base_url}/System/Info/Public"):
        print("Jellyfin not reachable — skipped", file=sys.stderr)
        return 0

    password = read_key_file(password_file)
    if not password:
        print("No Jellyfin admin password file — skipped", file=sys.stderr)
        return 0

    if os.environ.get("JELLYFIN_INTRO_SCAN_ONLY", "0") == "1":
        auth = _authenticate(base_url, username, password)
        if not auth:
            print("Jellyfin intro scan: auth failed", file=sys.stderr)
            return 1
        token, _ = auth
        _ensure_intro_pipeline(base_url, token)
        return 0

    public = _public_info(base_url)
    if not public.get("StartupWizardCompleted", False):
        if _complete_startup(base_url, username, password):
            print("Jellyfin admin ready for Seerr")
        auth = _authenticate(base_url, username, password)
        if auth:
            token, _ = auth
            _post_auth_setup(base_url, token)
        return 0

    auth = _authenticate(base_url, username, password)
    if auth:
        token, _ = auth
        print(f"Jellyfin admin password already valid ({username})")
        _post_auth_setup(base_url, token)
        return 0

    legacy_password = os.environ.get("JELLYFIN_LEGACY_PASSWORD", "")
    if legacy_password:
        legacy_auth = _authenticate(base_url, username, legacy_password)
        if legacy_auth:
            token, user_id = legacy_auth
            if _set_password(base_url, user_id, token, password, current_password=legacy_password):
                print(f"Jellyfin admin password migrated to declarative secret ({username})")
            _post_auth_setup(base_url, token)
            return 0

    print(
        "Jellyfin wizard completed but declarative password does not match — "
        "set JELLYFIN_LEGACY_PASSWORD once or fix jellyfin_admin_password",
        file=sys.stderr,
    )
    return 0


def main() -> None:
    raise SystemExit(setup_jellyfin())


if __name__ == "__main__":
    main()
