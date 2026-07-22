# ---
# id: 5035
# title: "Provision: Treiber pro API-Familie statt Skript pro Aufgabe"
# status: "accepted"
# note: "Entwurf, noch nicht gebaut"
# date: "2026-07-18"
# related: [5034, 5036, 5037]
# tags: ["provision", "treiber", "systemd", "oneshot", "arr", "prowlarr"]
# error_pattern: "provision|treiber|driver|arr-provision|oneshot|prowlarr.*sync"
# ---

# ADR-5035 — Provision: Treiber pro API-Familie statt Skript pro Aufgabe

**Kontext:** `525-provision/` + `packages/arr-provision/`

---

## Kontext

`packages/arr-provision/` besteht heute aus acht Python-Modulen, geschnitten nach
**Aufgabe** (keys, settings, download-clients, prowlarr, profiles, locale,
jellyfin, seerr), plus einem geteilten `common.py` (HTTP, Retry, Key-Dateien).

Jedes Modul ist genau ein CLI und genau eine systemd-Unit.

Beim Erweitern zeigt sich die Schwäche: Ein neuer Dienst derselben Familie
(Bazarr, Whisparr, Huntarr) zwingt dazu, mehrere Aufgaben-Skripte anzufassen,
obwohl er **dieselbe API** spricht wie Sonarr und Radarr.

## Entscheidung

Zwei Achsen sauber trennen:

1. **Aufgaben-Achse bleibt wie sie ist** — ein Modul pro systemd-Unit.
2. **Neue Treiber-Achse** — ein Modul pro **API-Familie**, nicht pro Dienst.

```
arr_provision/
├── common.py              # HTTP, Retry, Key-Dateien, URL-Bau  (existiert)
├── drivers/
│   ├── servarr.py         # sonarr · radarr · readarr · lidarr · prowlarr
│   ├── jellyfin.py
│   ├── seerr.py
│   └── sabnzbd.py
└── tasks/                 # 1:1 die systemd-Units, enthalten NUR Ablauf
    ├── keys.py
    ├── settings.py
    ├── download_clients.py
    ├── prowlarr.py
    ├── profiles.py
    ├── locale.py
    ├── jellyfin.py
    └── seerr.py
```

**Regel:** Treiber kennen *wie man mit einer API spricht*. Tasks kennen *was in
welcher Reihenfolge passieren soll*. Ein Task enthält keinen HTTP-Aufruf mehr
direkt, ein Treiber kennt keine Reihenfolge.

### Warum KEIN Über-Skript

Naheliegend wäre ein Orchestrator, der alle Tasks importiert und der Reihe nach
abarbeitet. **Bewusst verworfen:** Die Orchestrierung macht heute systemd —
Reihenfolge über `after`/`wants`, Wiederholung über `Restart=on-failure` +
`RestartSec` + `StartLimitBurst`, Schritt-Idempotenz über `RemainAfterExit`,
Sichtbarkeit über `systemctl status` je Schritt.

Ein Python-Orchestrator müsste das alles nachbauen und wäre schlechter darin.
Das widerspräche direkt dem Systemd-Maximalism-Prinzip („Policy und Lebenszyklus
gehören in systemd").

### Warum KEIN Skript pro Dienst

Sonarr, Radarr, Readarr, Lidarr und Prowlarr sind dieselbe Codebasis-Familie mit
derselben API (nur `v1` vs. `v3`). Ein Modul je Dienst würde diese eine API
fünfmal beschreiben. Die Varianz liegt in der **API**, nicht im Dienst.

---

## Treiber-Schnittstelle (verbindlich)

Jeder Treiber ist eine Klasse mit einheitlichem Konstruktor und diesen Methoden.
Wer implementiert, hält sich exakt daran — Tasks dürfen sich darauf verlassen.

### `drivers/servarr.py`

```python
class Servarr:
    def __init__(self, name: str, host: str, port: int,
                 api_version: str, api_key_file: str) -> None: ...

    # --- Basis ---
    def wait_ready(self) -> bool                       # nutzt common.wait_for_url
    def get(self, path: str) -> Any                    # relativ zu /api/<version>
    def put(self, path: str, body: Any) -> tuple[int, Any]
    def post(self, path: str, body: Any) -> tuple[int, Any]
    def delete(self, path: str) -> tuple[int, Any]

    # --- idempotente Bausteine (das eigentliche Wertvolle) ---
    def ensure(self, path: str, match_key: str, desired: dict) -> dict
        """GET path, Eintrag mit desired[match_key] suchen.
           Fehlt er -> POST. Existiert er und weicht ab -> PUT mit gemergter id.
           Gleich -> nichts tun. Gibt den finalen Eintrag zurueck."""

    def resolve_id(self, path: str, name: str) -> int | None
        """Namen -> numerische id (Quality-Profile, Root-Folder, Tags)."""

    def ensure_root_folder(self, path: str) -> int
    def config_xml_path(self) -> Path                  # /var/lib/<name>/config.xml
    def set_api_key_in_config(self, key: str) -> bool  # True wenn geaendert
    def restart_unit(self) -> None                     # systemctl restart <name>
```

`ensure()` ist der Kern. Fast jede Provisionierungs-Operation ist „lege an, wenn
es fehlt; gleiche an, wenn es abweicht; fasse nichts an, wenn es passt".

### `drivers/jellyfin.py`

```python
class Jellyfin:
    def __init__(self, host, port, admin_user, admin_password_file) -> None
    def wait_ready(self) -> bool
    def is_initialized(self) -> bool          # Startup-Wizard schon durch?
    def bootstrap_admin(self) -> None
    def authenticate(self) -> str             # gibt Access-Token zurueck
    def ensure_library(self, name: str, kind: str, path: str) -> None
    def ensure_user(self, name: str, password_file: str) -> None
    def set_metadata_locale(self, language: str, country: str) -> None
    def trigger_task(self, task_name: str) -> None   # Intro-/Kapitel-Scan
```

### `drivers/seerr.py`

```python
class Seerr:
    def __init__(self, host, port) -> None
    def wait_ready(self) -> bool
    def is_initialized(self) -> bool
    def login(self, user: str, password_file: str) -> None   # Cookie-Session
    def init_with_jellyfin(self, cfg: dict) -> None
    def ensure_service(self, kind: str, cfg: dict) -> None   # kind: sonarr|radarr
```

### `drivers/sabnzbd.py`

```python
class Sabnzbd:
    def __init__(self, host, port, api_key_file) -> None
    def wait_ready(self) -> bool
    def get_config(self) -> dict
    def ensure_categories(self, categories_ini: str) -> bool
    def set_language(self, lang: str) -> bool
    def restart_unit(self) -> None
```

---

## Migrations-Abbildung

Wer baut, verschiebt Logik nach dieser Tabelle. Nichts wird neu erfunden.

| Heute | Logik wandert nach | Task behält |
|-------|--------------------|-------------|
| `arr_keys_sync.py` | `Servarr.set_api_key_in_config`, `.restart_unit` | Schleife über aktive Dienste, Env lesen |
| `arr_settings_sync.py` | `Servarr.ensure` (config/host, config/naming) | welche Settings, welche Werte |
| `download_clients.py` | `Servarr.ensure("downloadclient", …)`, `Sabnzbd` | Ziel-Liste aus `TARGETS_JSON` |
| `profile_sync.py` | `Servarr.resolve_id`, `.ensure` | Bulk-Zuweisung, Fallback-Profil-Logik |
| `prowlarr_sync.py` | `Servarr` (Prowlarr ist Familie!) + sqlite-Sonderfall | Indexer/Apps aus JSON, Sync-Level |
| `jellyfin_setup.py` | `Jellyfin.*` | Bibliotheks-Pfade, Extra-User, Scan-Flags |
| `seerr_sync.py` | `Seerr.*` | `SEERR_CONFIG_JSON` auspacken |
| `locale_sync.py` | `Jellyfin.set_metadata_locale`, `Sabnzbd.*` | welche Ziele aktiv sind |

---

## Verbindliche Verträge (nicht verhandelbar)

1. **Systemd-Unit-Grenzen bleiben unverändert.** Acht Units, gleiche Namen,
   gleiche `after`/`wants`. Der Refactor ist rein intern.
2. **Env-Var-Kontrakt aus Nix bleibt unverändert.** Die Namen in
   `525-provision/*.nix` (`SONARR_KEY_FILE`, `TARGETS_JSON`, …) sind die
   Schnittstelle. Wer sie ändert, muss Nix und Python gemeinsam ändern.
3. **Nur stdlib.** Keine externen Python-Abhängigkeiten. Kein `requests`,
   kein `pydantic`. Das hält das Closure klein und den Build reproduzierbar.
4. **Idempotenz ist Pflicht.** Zweiter Lauf darf nichts ändern. Jede Operation
   geht über `ensure()` oder ein Äquivalent — niemals blindes POST.
5. **Secrets nur als Dateipfade.** Niemals ein Key als Env-Wert oder Argument
   (landet sonst in `/proc/<pid>/environ` bzw. in der Prozessliste).

---

## Neuen Dienst hinzufügen — das Rezept

Ziel dieser ADR: Das hier soll in Minuten gehen, nicht in Stunden.

**Fall A — Servarr-Familie (Bazarr, Whisparr, Huntarr):**
1. `default.nix`: `enable` + `package` + Port ergänzen.
2. `lib/service-tiers.nix`: Tier eintragen (meist `backend-lan`).
3. `525-provision/*.nix`: Dienst in die jeweiligen Ziel-Listen aufnehmen.
4. **Python: nichts.** Der `Servarr`-Treiber spricht die API bereits.

**Fall B — fremde API:**
1. Schritte 1–3 wie oben.
2. `drivers/<name>.py` anlegen, Schnittstelle oben spiegeln.
3. Task ergänzen, der den Treiber benutzt.

---

## Bekannte Fallstricke (für die Umsetzung)

- **API-Version:** Sonarr/Radarr sind `v3`, Readarr/Lidarr/Prowlarr `v1`.
  Gehört in den Konstruktor, nicht in jeden Aufruf.
- **Prowlarr braucht SQLite-Zugriff** (`/var/lib/prowlarr/prowlarr.db`) für Dinge,
  die die API nicht hergibt. Das bleibt ein dokumentierter Sonderfall im
  Prowlarr-Task, nicht im Treiber.
- **ID-Auflösung ist die Hauptfehlerquelle.** Profilnamen und Root-Ordner müssen
  zu numerischen IDs werden, und die entstehen erst, wenn Recyclarr durch ist.
  Deshalb die `after=`-Kette im Nix — nicht antasten.
- **Seerr nutzt Cookie-Sessions**, keinen API-Key-Header. Eigener Auth-Pfad.
- **Jellyfin-Startup-Wizard** ist einmalig und nicht wiederholbar. `is_initialized()`
  muss zuverlässig sein, sonst bricht der zweite Lauf.

---

## Konsequenzen

**Positiv**
- Neuer Servarr-Dienst = null Python.
- `ensure()` einmal richtig statt achtmal ähnlich.
- Treiber sind einzeln testbar (relevant für #48).

**Negativ**
- Refactor von funktionierendem Code; die Risikostellen sind genau die
  fummeligen (ID-Auflösung, Idempotenz-Grenzfälle).
- Kurzzeitig zwei Strukturen parallel, wenn schrittweise migriert wird.

**Empfohlene Reihenfolge beim Bau**
`servarr.py` zuerst (deckt fünf Dienste ab, größter Hebel), dann `sabnzbd.py`,
dann `jellyfin.py`, zuletzt `seerr.py` (komplexeste Auth).
