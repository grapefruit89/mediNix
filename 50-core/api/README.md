# Archivierte API-Specs — ⚠ UNVOLLSTÄNDIG

## Was hier liegt

| Datei | Quelle | Zustand |
|-------|--------|---------|
| `radarr-api-v3.partial.json` | Radarr `develop`, Api.V3 | ⚠ **abgeschnitten bei ~115 KB**, letzter Pfad `/api/v3/movie`, **kein gültiges JSON** |
| `prowlarr-api-v1.json` | Prowlarr `develop`, Api.V1 | ⚠ **abgeschnitten bei ~113 KB**, letzter Pfad `/api/v1/log/file/update`, **kein gültiges JSON** |

**Beide Dateien sind Auszüge, keine vollständigen Specs.** Sie wurden mit einem
Werkzeug geholt, das bei ~115 KB hart abschneidet; die echten Specs sind größer.
Ein `jq`/`ConvertFrom-Json` auf diese Dateien schlägt fehl — das ist erwartet.

**Sonarr fehlt ganz:** Der Abruf lief in einen Timeout (Spec zu groß).

## Wofür sie trotzdem taugen

Als **Nachschlagewerk für die Endpunkte, die tatsächlich drinstehen**. Genau
darauf stützt sich der verifizierte Teil von `../api-reference.md` — inklusive
Zeilennummern, damit jede Behauptung nachprüfbar ist.

Was sie **nicht** sind: eine belastbare Grundlage für Feldnamen und Pflichtfelder
von Endpunkten, die jenseits des Abschnitts liegen.

## Vollständige Specs holen

Auf einem System ohne Größenlimit (also praktisch jedem):

```bash
cd 50-core/api

curl -fsSL -o radarr-api-v3.json \
  https://raw.githubusercontent.com/Radarr/Radarr/develop/src/Radarr.Api.V3/openapi.json

curl -fsSL -o sonarr-api-v3.json \
  https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V3/openapi.json

curl -fsSL -o prowlarr-api-v1.json \
  https://raw.githubusercontent.com/Prowlarr/Prowlarr/develop/src/Prowlarr.Api.V1/openapi.json

# Vollständigkeit prüfen -- muss ohne Fehler durchlaufen:
for f in *.json; do jq -e . "$f" >/dev/null && echo "OK   $f" || echo "KAPUTT $f"; done
```

Danach die `.partial`-Auszüge löschen und in `../api-reference.md` die
⚠️-Markierungen auf ✅ setzen — mit den dann tatsächlich verifizierten Feldnamen.

## Wichtiger als jede Spec: die laufende Instanz

`develop` kann **neuer sein als die installierte Version**. Autoritativ für das,
was auf diesem System läuft, ist die Instanz selbst:

```bash
KEY=$(cat /var/lib/secrets/radarr_api_key)
curl -s -H "X-Api-Key: $KEY" http://127.0.0.1:5004/api/v3/system/status | jq .version
curl -s -H "X-Api-Key: $KEY" http://127.0.0.1:5004/api/v3/qualityprofile | jq '.[0] | keys'
```

Manche Servarr-Versionen liefern ihre eigene Spec unter `/api/v3/openapi.json` —
das ist dann die genaueste verfügbare Quelle.

## Warum das hier überhaupt archiviert wird

Siehe `../../AGENTS.md`, Regel 0: Niemals aus dem Gedächtnis, immer aus der
Primärquelle. Eine im Repo liegende — auch unvollständige — Spec mit ehrlicher
Zustandsangabe ist einer Vermutung immer überlegen. Die Quell-URLs oben dürfen
bei Refactorings **nicht** entfernt werden.
