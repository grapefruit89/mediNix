# API-Referenz für die Provisionierung

Verbindliche Grundlage für `525-provision/`, `packages/arr-provision/` und die
Treiber-Implementierung aus **ADR-5035**.

> ## ⚠ Grundregel
>
> **Niemals aus dem Gedächtnis. Immer aus der Originalquelle.**
>
> API-Schemata der *arr-Familie ändern sich zwischen Versionen. Ein Modell, das
> Feldnamen „aus dem Kopf" nennt, liegt irgendwann falsch — und der Fehler zeigt
> sich erst zur Laufzeit, beim ersten Download, im schlimmsten Fall Wochen später.
>
> Diese Datei sagt bei **jedem** Eintrag, woher er stammt und ob er verifiziert ist.
> Was nicht verifiziert ist, ist als solches markiert und **muss** vor der
> Umsetzung geprüft werden.

---

## 1. Originalquellen — niemals entfernen

Diese URLs sind Teil der Architektur. Sie gehören in jede abgeleitete Datei als
Kommentar und dürfen bei Refactorings nicht wegfallen.

```
# === PRIMÄRQUELLEN — NICHT ENTFERNEN ===
# Radarr   OpenAPI : https://raw.githubusercontent.com/Radarr/Radarr/develop/src/Radarr.Api.V3/openapi.json
# Radarr   Doku    : https://radarr.video/docs/api/
# Sonarr   OpenAPI : https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V3/openapi.json
# Sonarr   Doku    : https://sonarr.tv/docs/api/#v3
# Prowlarr OpenAPI : https://raw.githubusercontent.com/Prowlarr/Prowlarr/develop/src/Prowlarr.Api.V1/openapi.json
# Prowlarr Doku    : https://prowlarr.com/docs/api/
# Lidarr / Readarr : gleiche Struktur, Api.V1
# ========================================
```

### Die eigentlich beste Quelle: die laufende Instanz

Die Specs oben folgen `develop` und können **neuer sein als die installierte
Version**. Autoritativ für das, was auf *diesem* System läuft, ist die Instanz
selbst:

```bash
curl -s -H "X-Api-Key: $(cat /var/lib/secrets/radarr_api_key)" \
     http://127.0.0.1:5004/api/v3/system/status | jq .version
```

**Regel für die Umsetzung:** Bei jedem Zweifel gegen die laufende Instanz prüfen,
nicht gegen `develop`.

---

## 2. Verifikationsstand dieser Datei

| Spec | Stand | Abdeckung |
|------|-------|-----------|
| **Prowlarr v1** | ✅ abgerufen, 5048 Zeilen | weitgehend vollständig — Inventar unten ist verifiziert |
| **Radarr v3** | ⚠️ abgerufen, aber **abgeschnitten** bei `/api/v3/movie` | alles alphabetisch danach (`qualityprofile`, `rootfolder`, `system/status`, `tag`) **nicht** verifiziert |
| **Sonarr v3** | ❌ nicht abrufbar (Timeout, Spec zu groß) | keine Verifikation |

**Konsequenz:** Die Prowlarr-Tabelle unten ist belastbar. Die Radarr/Sonarr-Tabelle
enthält verifizierte *und* unverifizierte Zeilen — beide sind gekennzeichnet.

---

## 3. Gemeinsames der Servarr-Familie

Sonarr, Radarr, Readarr, Lidarr und Prowlarr teilen sich ein Framework. Deshalb
ein Treiber für alle fünf (ADR-5035).

| Aspekt | Wert |
|--------|------|
| Base-URL | `http://<host>:<port>/api/<version>` |
| **API-Version** | Sonarr `v3`, Radarr `v3`, **Prowlarr `v1`**, Lidarr `v1`, Readarr `v1` |
| Auth | Header `X-Api-Key: <key>` |
| Key-Herkunft | `config.xml` bzw. Env `<APP>__AUTH__APIKEY` |
| Fehlerformat | HTTP-Status + JSON-Body |

**Falle:** Die Version ist pro Dienst verschieden. Sie gehört in den
Treiber-Konstruktor, **nicht** in jeden einzelnen Aufruf — sonst schleicht sich
irgendwo `v3` bei Lidarr ein und schlägt erst zur Laufzeit fehl.

---

## 4. Prowlarr v1 — verifiziertes Inventar

Aus der abgerufenen Spec, Zeilennummern zur Nachprüfung.

| Endpunkt | Zeile | Zweck bei uns |
|----------|-------|---------------|
| `/api/v1/system/status` | 3588 | Bereitschaft abwarten ✅ |
| `/api/v1/indexer` | 1808 | Indexer auflisten / anlegen |
| `/api/v1/indexer/{id}` | 1713 | Indexer ändern / löschen |
| `/api/v1/indexer/schema` | 1913 | **Feldliste je Implementation** |
| `/api/v1/indexer/test` | 1935 | vor dem Speichern validieren |
| `/api/v1/indexer/bulk` | 1866 | Massenänderung |
| `/api/v1/indexer/categories` | 2009 | Newznab-Kategorien |
| `/api/v1/applications` | 148 | *arr als Application registrieren |
| `/api/v1/applications/{id}` | 53 | Application ändern |
| `/api/v1/applications/schema` | 253 | **Feldliste** |
| `/api/v1/applications/test` | 275 | validieren |
| `/api/v1/appprofile` | 349 | Sync-Profile |
| `/api/v1/appprofile/schema` | 500 | Feldliste |
| `/api/v1/downloadclient` | 1087 | Download-Client |
| `/api/v1/downloadclient/schema` | 1192 | Feldliste |
| `/api/v1/config/host` | 1694 | Host-Settings |

---

## 5. Radarr / Sonarr v3

| Endpunkt | Zweck | Verifikation |
|----------|-------|--------------|
| `/api/v3/downloadclient` | Client auflisten / anlegen | ✅ Radarr-Spec Z. 1860 |
| `/api/v3/downloadclient/{id}` | ändern / löschen | ✅ Z. 1918 |
| `/api/v3/downloadclient/schema` | **Feldliste** | ✅ Z. 2071 |
| `/api/v3/downloadclient/test` | validieren | ✅ Z. 2093 |
| `/api/v3/downloadclient/bulk` | Massenänderung | ✅ Z. 2024 |
| `/api/v3/config/host` | TRaSH-Host-Settings | ✅ Z. 2665 |
| `/api/v3/indexer` | Indexer (Backup-Indexer) | ✅ Z. 3566 |
| `/api/v3/indexer/schema` | Feldliste | ✅ Z. 3777 |
| `/api/v3/movie` | Bibliothek lesen | ✅ Z. 4902 |
| `/api/v3/system/status` | Bereitschaft abwarten | ⚠️ **analog** zu Prowlarr (dort verifiziert) — gegenprüfen |
| `/api/v3/qualityprofile` | Profilname → ID | ⚠️ **nicht verifiziert** |
| `/api/v3/rootfolder` | Root-Ordner lesen/anlegen | ⚠️ **nicht verifiziert** |
| `/api/v3/series` (Sonarr) | Bibliothek lesen | ⚠️ **nicht verifiziert** |
| Bulk-Edit der Bibliothek | Profil-Zuweisung | ⚠️ Endpunktname **unklar** — prüfen |

**Die vier ⚠️-Zeilen sind Pflichtprüfung vor der Implementierung.** Verfahren
siehe Abschnitt 8.

---

## 6. Das Kernmuster: `/schema` + `/test` statt blindem POST

Der wichtigste Fund aus den Specs. Sowohl Download-Clients als auch Indexer und
Applications bieten `/schema` **und** `/test`. Damit wird `ensure()` aus ADR-5035
versionsfest:

```
1. GET  /<resource>/schema
      → Liste der Feld-Definitionen für die gewünschte Implementation
        (z.B. "Sabnzbd"), inklusive Pflichtfeldern und Defaults

2. Felder aus unserer Nix-Config füllen
      → Host, Port, Kategorie, API-Key (aus Datei gelesen)

3. POST /<resource>/test
      → validieren, BEVOR gespeichert wird

4. GET  /<resource>
      → existiert ein Eintrag mit diesem Namen bereits?

5. fehlt      → POST /<resource>
   weicht ab  → PUT  /<resource>/{id}   (id aus Schritt 4 übernehmen!)
   identisch  → nichts tun
```

**Warum das der Unterschied zwischen fragil und robust ist:** Feldnamen und
Pflichtfelder der Implementations sind versionsabhängig. Wer sie im Python
hartcodiert, bricht beim nächsten Update. Wer sie zur Laufzeit aus `/schema`
holt, überlebt es.

Schritt 3 verhindert zusätzlich die Fehlerklasse „Eintrag ist angelegt, sieht gut
aus, schlägt aber erst beim ersten echten Download fehl".

Schritt 5 ist der Idempotenz-Kern: **niemals blind POST**, sonst entstehen bei
jedem Rebuild Duplikate.

---

## 7. Nicht-Servarr-APIs

| App | Auth | Besonderheit |
|-----|------|--------------|
| **SABnzbd** | `apikey` als **Query-Parameter** | Kein REST. Alles über `/api?mode=<befehl>&apikey=…&output=json`. Kategorien werden über die ini-Struktur gesetzt. |
| **Jellyfin** | `X-Emby-Token` nach Login | Der Startup-Wizard ist **einmalig und nicht wiederholbar**. `is_initialized()` muss zuverlässig sein, sonst bricht der zweite Lauf. |
| **Jellyseerr** | **Cookie-Session** | Kein API-Key-Header. Login setzt ein Cookie, das mitgeführt werden muss — daher `http.cookiejar` in `seerr_sync.py`. |

---

## 8. Verifikationsverfahren für die Umsetzung

Für jede ⚠️-Zeile aus Abschnitt 5, gegen die **laufende Instanz**:

```bash
KEY=$(cat /var/lib/secrets/radarr_api_key)
BASE=http://127.0.0.1:5004/api/v3

# 1. Existiert der Endpunkt überhaupt?
curl -s -o /dev/null -w '%{http_code}\n' -H "X-Api-Key: $KEY" "$BASE/qualityprofile"

# 2. Welche Felder liefert er wirklich?
curl -s -H "X-Api-Key: $KEY" "$BASE/qualityprofile" | jq '.[0] | keys'

# 3. Feldschema für eine Implementation
curl -s -H "X-Api-Key: $KEY" "$BASE/downloadclient/schema" \
  | jq '.[] | select(.implementation=="Sabnzbd") | .fields[] | {name, value, type}'
```

**Ergebnis dieser Prüfung gehört zurück in diese Datei** — Zeile von ⚠️ auf ✅
setzen und die tatsächlichen Feldnamen notieren. Diese Datei ist ein lebendes
Dokument, kein Einmal-Artefakt.

---

## 9. Offene Frage aus dem Ist-Zustand

Der API-Key wird derzeit auf **zwei** Wegen gesetzt:

1. `EnvironmentFile` → `<APP>__AUTH__APIKEY` (erzeugt von `secrets-generator.nix`)
2. `arr_keys_sync.py` schreibt ihn zusätzlich in `config.xml` und startet neu

Ob beides nötig ist, ist **nicht verifiziert**. Zwei Möglichkeiten:

- Die Env-Variante reicht bei aktuellen Versionen → der `config.xml`-Weg samt
  Restart-Zyklus kann entfallen (spart Neustarts bei jedem Rebuild).
- Die Env-Variable greift nicht überall → beide Wege bleiben nötig, dann aber
  bitte mit Kommentar, *warum*.

**Vor dem Treiber-Refactor klären.** Prüfung: Key nur per Env setzen, Dienst
starten, `GET /system/status` mit diesem Key — kommt 200, reicht Env allein.

---

## 10. Sicherheitsregel (nicht verhandelbar)

API-Keys **niemals** als Env-Wert oder Kommandozeilen-Argument übergeben. Sie
landen sonst in `/proc/<pid>/environ` und in der Prozessliste, für jeden lesbar,
der auf der Maschine ein `ps` absetzen kann.

Immer als **Dateipfad** (`*_KEY_FILE`), den der Treiber selbst liest. So ist es
heute umgesetzt und so muss es bleiben (ADR-5035, Vertrag 5).
