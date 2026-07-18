# API-Referenz für die Provisionierung

Was `525-provision/` bzw. `packages/arr-provision/` tatsächlich an APIs anspricht.
Grundlage für die Treiber-Implementierung aus **ADR-5035**.

> **Verlasst euch nicht auf das Gedächtnis eines Modells für API-Schemata.**
> Das ist genau die Fehlerklasse, die teuer wird. Die Spalte „Quelle" sagt, was
> gegen die echte OpenAPI-Spec geprüft ist und was noch zu verifizieren ist.

## Spec-Quellen (pinnen!)

| App | OpenAPI | Doku |
|-----|---------|------|
| Radarr | `https://raw.githubusercontent.com/Radarr/Radarr/develop/src/Radarr.Api.V3/openapi.json` | https://radarr.video/docs/api/ |
| Sonarr | (analog `Sonarr.Api.V3`) | https://sonarr.tv/docs/api/#v3 |
| Prowlarr | `https://raw.githubusercontent.com/Prowlarr/Prowlarr/develop/src/Prowlarr.Api.V1/openapi.json` | https://prowlarr.com/docs/api/ |

**TODO für die Umsetzung:** Diese drei Specs versioniert ins Repo legen
(`docs/api/<app>-openapi.json`) und mit Datum/Commit pinnen. Die Specs folgen
`develop` und ändern sich — ohne Pin baut man gegen ein bewegliches Ziel.

---

## Gemeinsames für die Servarr-Familie

- **Auth:** Header `X-Api-Key: <key>`. Der Key steht in `config.xml` bzw. kommt
  über `<APP>__AUTH__APIKEY`.
- **API-Version:** Sonarr/Radarr = `v3`, Prowlarr/Lidarr/Readarr = `v1`.
  Gehört in den Treiber-Konstruktor, nicht in jeden Aufruf (ADR-5035).
- **Base:** `http://<host>:<port>/api/<version>`

---

## Endpunkte je Operation

| Operation | Endpunkt | Methode | Quelle |
|-----------|----------|---------|--------|
| Bereitschaft abwarten | `/system/status` | GET | ⚠️ zu verifizieren |
| Download-Client anlegen/ändern | `/downloadclient` | GET, POST | ✅ Spec |
| Download-Client einzeln | `/downloadclient/{id}` | GET, PUT, DELETE | ✅ Spec |
| **Feld-Schema holen** | `/downloadclient/schema` | GET | ✅ Spec |
| **Vor dem Speichern testen** | `/downloadclient/test` | POST | ✅ Spec |
| Massen-Änderung | `/downloadclient/bulk` | PUT | ✅ Spec |
| Host-Settings (TRaSH) | `/config/host` | GET, PUT | ✅ Spec |
| Indexer | `/indexer`, `/indexer/{id}` | GET, POST, PUT | ✅ Spec |
| Indexer-Schema / Test | `/indexer/schema`, `/indexer/test` | GET, POST | ✅ Spec |
| Bibliothek (Filme) | `/movie` | GET | ✅ Spec |
| Quality-Profile auflösen | `/qualityprofile` | GET | ⚠️ zu verifizieren |
| Root-Ordner | `/rootfolder` | GET, POST | ⚠️ zu verifizieren |

⚠️ = aus allgemeiner Kenntnis, in dieser Sitzung **nicht** gegen die Spec geprüft
(der Fetch der Radarr-Spec brach vor diesen Einträgen ab). Vor der Implementierung
gegen die gepinnte Spec gegenprüfen.

---

## Der wichtigste Fund: `/schema` + `/test`

Für Download-Clients und Indexer gibt es **beides**. Damit wird `ensure()` aus
ADR-5035 deutlich robuster als blindes POST:

```
1. GET  /downloadclient/schema      → Feldliste für die Implementation (z.B. SABnzbd)
2.      Felder mit unseren Werten füllen (Host, Port, Kategorie, API-Key)
3. POST /downloadclient/test        → validieren, BEVOR gespeichert wird
4. GET  /downloadclient             → existiert der Eintrag schon (Name-Match)?
5. POST bzw. PUT /downloadclient/{id}
```

**Warum das zählt:** Die Feldnamen und Pflichtfelder der Implementations sind
versionsabhängig. Wer sie hart im Python-Code führt, bricht bei jedem
Radarr-Update. Wer das Schema zur Laufzeit holt, überlebt es. Das gehört als
Standardvorgehen in `Servarr.ensure()`.

`/test` erspart zusätzlich die Klasse „Eintrag ist angelegt, aber falsch
konfiguriert und schlägt erst beim ersten Download fehl".

---

## Nicht-Servarr-APIs

| App | Auth | Besonderheit |
|-----|------|--------------|
| **SABnzbd** | `apikey` als Query-Parameter | JSON-API über `/api?mode=...`, nicht REST |
| **Jellyfin** | `X-Emby-Token` nach Login | Startup-Wizard einmalig, nicht wiederholbar → `is_initialized()` muss zuverlässig sein |
| **Jellyseerr** | **Cookie-Session**, kein API-Key-Header | eigener Login-Pfad; erklärt `http.cookiejar` in `seerr_sync.py` |

---

## Offene Frage aus dem Ist-Zustand

Der API-Key wird derzeit auf **zwei** Wegen gesetzt:

1. `EnvironmentFile` → `<APP>__AUTH__APIKEY` (aus `secrets-generator.nix`)
2. `arr_keys_sync.py` schreibt ihn zusätzlich in `config.xml` und startet den Dienst neu

Ob beides nötig ist, ist **nicht verifiziert**. Möglich ist: die Env-Variante
allein reicht bei aktuellen Versionen, und der `config.xml`-Weg ist ein Relikt.
Oder umgekehrt: die Env-Variable greift nicht überall.

**Vor dem Treiber-Refactor klären** — wenn ein Weg entfallen kann, spart das den
kompletten Restart-Zyklus aus `arr_keys_sync`.

---

## Sicherheitsregel

API-Keys **niemals** als Env-Wert oder Kommandozeilen-Argument übergeben — sie
landen sonst in `/proc/<pid>/environ` und in der Prozessliste. Immer als
**Dateipfad** (`*_KEY_FILE`), den der Treiber selbst liest. So ist es heute
umgesetzt und so muss es bleiben (ADR-5035, Vertrag 5).
