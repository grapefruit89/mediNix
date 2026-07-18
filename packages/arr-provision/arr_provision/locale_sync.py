"""Jellyfin locale and SABnzbd category sync."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def sync_jellyfin_locale(lang: str, country: str, ui_culture: str) -> None:
    path = Path("/var/lib/jellyfin/config/system.xml")
    if not path.exists():
        print(f"Jellyfin system.xml not found: {path} — skipped", file=sys.stderr)
        return

    ET.register_namespace("", "")
    tree = ET.parse(path)
    root = tree.getroot()
    changes = 0
    for tag, value in (
        ("PreferredMetadataLanguage", lang),
        ("MetadataCountryCode", country),
        ("UICulture", ui_culture),
    ):
        element = root.find(tag)
        if element is not None and element.text != value:
            element.text = value
            changes += 1

    if changes:
        tree.write(path, encoding="utf-8", xml_declaration=True)
        print(f"Jellyfin system.xml: updated {changes} fields ({lang}/{country}/{ui_culture})")
    else:
        print(f"Jellyfin system.xml: already correct ({lang}/{country}/{ui_culture})")


def sync_sabnzbd_locale(lang: str, categories_ini: str, sab_key_file: str) -> None:
    sab_ini = Path("/var/lib/sabnzbd/sabnzbd.ini")
    if not sab_ini.exists():
        print("sabnzbd.ini not present — skipped (SABnzbd not initialized)", file=sys.stderr)
        return

    content = sab_ini.read_text(encoding="utf-8")
    changed = False

    if re.search(r"^language", content, flags=re.MULTILINE):
        updated = re.sub(r"^language.*$", f"language = {lang}", content, count=1, flags=re.MULTILINE)
        if updated != content:
            content = updated
            changed = True
    else:
        content = f"language = {lang}\n{content}"
        changed = True

    key_path = Path(sab_key_file)
    if key_path.exists():
        sab_key = key_path.read_text(encoding="utf-8").strip()
        for key_name in ("api_key", "nzb_key"):
            pattern = rf"^{re.escape(key_name)}.*$"
            replacement = f"{key_name} = {sab_key}"
            if re.search(pattern, content, flags=re.MULTILINE):
                updated = re.sub(pattern, replacement, content, count=1, flags=re.MULTILINE)
                if updated != content:
                    content = updated
                    changed = True
            else:
                content = f"{key_name} = {sab_key}\n{content}"
                changed = True
        print("SABnzbd: API keys updated")

    if "[categories]" not in content:
        content = content.rstrip() + "\n\n" + categories_ini + "\n"
        changed = True
        print("SABnzbd: categories inserted")
    else:
        print("SABnzbd: categories already present")

    if changed:
        sab_ini.write_text(content, encoding="utf-8")
        print(f"SABnzbd: language set to {lang}, restarting service")
        subprocess.run(["systemctl", "restart", "sabnzbd.service"], check=False)
    else:
        print(f"SABnzbd: already correct ({lang})")


def sync_locale() -> int:
    lang = os.environ["TARGET_LANG"]
    locale = os.environ["TARGET_LOCALE"]
    country = locale.split("_")[1].upper() if "_" in locale else lang.upper()
    ui_culture = locale.replace("_", "-").removesuffix(".UTF-8")

    if os.environ.get("SYNC_JELLYFIN", "0") == "1":
        print("=== Jellyfin locale sync ===")
        sync_jellyfin_locale(lang, country, ui_culture)

    if os.environ.get("SYNC_SABNZBD", "0") == "1":
        print("=== SABnzbd locale sync ===")
        sync_sabnzbd_locale(lang, os.environ["CATEGORIES_INI"], os.environ.get("SAB_KEY_FILE", ""))

    print("Locale sync complete.")
    return 0


def main() -> None:
    raise SystemExit(sync_locale())


if __name__ == "__main__":
    main()