# ADR-5036 — Glühbirnen-API: die minimale Pflichtkonfiguration

**Status:** accepted (Entwurf, noch nicht gebaut)
**Datum:** 2026-07-18
**Betrifft:** `default.nix`, `530-sabnzbd/`, `560-recyclarr/`, `525-provision/`
**Verwandt:** ADR-5035 (Treiber-Architektur), Issue #49

---

## Kontext

Ein Nutzer soll `enable = true` setzen und einen laufenden Stack bekommen.
Vollständige Null-Konfiguration ist bei einem Media-Stack unmöglich — irgendjemand
muss sagen, wo die Filme liegen und mit welchem Usenet-Zugang geladen wird.

Die Frage ist also nicht *ob* es Pflichtoptionen gibt, sondern **welche wirklich
unvermeidbar sind**. Alles andere ist vorhersehbar und gehört automatisiert.

## Die Analyse: Was variiert wirklich pro Installation?

| Bereich | Variiert? | Begründung |
|---------|-----------|------------|
| Usenet-Provider (Host, Port, SSL, Zugang) | **JA** | individueller Vertrag |
| Usenet-Indexer (URL, API-Key) | **JA** | individuelles Abo |
| Sprache der gewünschten Releases | **JA** | persönliche Präferenz |
| Zielauflösung | **JA** | Hardware/Geschmack |
| Wo die Medien liegen | **JA** (mit Default) | Storage-Layout |
| Domain für HTTPS/WAN | optional | `null` = nur `.local`, funktioniert sofort |
| GPU-Vendor | optional (mit Fallback) | Software-Transcode als Rückfall |
| **Ports, User, Hardening, systemd, RAM-Limits, Ingress, mDNS, VPN-Sandbox, Leak-Verify, tmpfs-Transcode, Secrets-Generator, Observability** | **NEIN** | vorhersehbar, gehört ins Modul |

**Ergebnis: fünf Pflichtblöcke, alles andere abgeleitet.**

---

## Entscheidung: Die Glühbirnen-API

```nix
grapefruitMedia = {
  enable = true;

  # ── 1. Usenet-Zugang (Pflicht, wenn heruntergeladen werden soll) ──
  usenet.provider = {
    host = "news.example.com";
    port = 563;                              # Default
    ssl = true;                              # Default
    usernameFile = "/run/secrets/usenet-user";
    passwordFile = "/run/secrets/usenet-pass";
    connections = 16;                        # Default, siehe unten
  };

  # ── 2. Indexer (Pflicht, sonst wird nichts gefunden) ──
  usenet.indexers = [
    { name = "nzbgeek";
      baseUrl = "https://api.nzbgeek.info";
      apiKeyFile = "/run/secrets/nzbgeek-key"; }
  ];

  # ── 3. Präferenzen (Pflicht — bestimmt die Profile) ──
  preferences = {
    language = "de";                 # "de" | "en"
    quality = "1080p";               # "1080p" | "2160p"
    languageMode = "required";       # Default, siehe Semantik unten
  };

  # ── 4. Storage (Default vorhanden) ──
  storage.mediaRoot = "/data";

  # ── 5. Dienste (Preset statt Einzelschalter) ──
  preset = "usenet-media";           # aktiviert das Standard-Bündel
};
```

Alles andere hat Defaults.

### `preset`

| Wert | Aktiviert |
|------|-----------|
| `"usenet-media"` | jellyfin, jellyseerr, sonarr, radarr, prowlarr, sabnzbd, recyclarr, provision |
| `"arr-only"` | sonarr, radarr, prowlarr, sabnzbd, recyclarr, provision — kein Player |
| `"none"` (Default) | nichts; Einzelschalter wie bisher |

Ein Preset setzt die Einzelschalter per `lib.mkDefault` — der Nutzer kann jeden
davon einzeln überstimmen. Kein Entweder-oder.

---

## ⚠ Drei Fallen im ursprünglichen Entwurf

Diese drei Punkte kamen aus einem KI-Entwurf und **dürfen nicht so gebaut werden**.

### 1. `fileContents` auf Secrets = Secret im Nix-Store (kritisch)

Der Entwurf schlug vor:
```nix
username = fileContents "/var/lib/secrets/usenet-username";   # ❌ NIEMALS
```

`builtins.readFile` und `lib.fileContents` werden zur **Evaluationszeit**
ausgewertet. Das Ergebnis landet im **world-readable `/nix/store`** — das
Usenet-Passwort wäre für jeden lesbar, der auf der Maschine `cat` bedienen kann.
Und es bliebe dort, auch nach dem Ändern des Passworts.

**Korrekt:** Das Modul kennt nur den **Pfad**. Der Wert wird zur **Laufzeit**
gelesen — von der Provisionierung (`525-provision`), die ihn per API in SABnzbd
schreibt, oder über `EnvironmentFile`/`LoadCredential`.

> Das ist derselbe Vertrag wie in ADR-5035 (Vertrag 5) und AGENTS.md (Regel 4):
> **Secrets nur als Dateipfade, niemals als Werte in der Nix-Config.**

### 2. Erfundene `trash_ids`

Der Entwurf enthielt u.a. `"4c1f9a8f3b2d4e5f6a7b8c9d0e1f2a3b"` — explizit als
„Beispiel-ID" markiert. Eine falsche `trash_id` führt dazu, dass Recyclarr das
Custom Format **stillschweigend nicht anwendet**. Der Fehler zeigt sich erst
daran, dass wochenlang die falschen Releases geladen werden.

**Regel:** Jede `trash_id` kommt aus den TRaSH-Guides (Repo `TRaSH-Guides/Guides`,
`docs/json/radarr|sonarr/cf/*.json`) und wird mit Datum vermerkt. Nichts aus dem
Gedächtnis. Siehe AGENTS.md Regel 0.

Die in diesem ADR genannten IDs sind **ungeprüft** und vor der Umsetzung gegen
die Quelle zu verifizieren.

### 3. Auflösungen über negative Scores ausschließen

Der Entwurf wollte 4k im 1080p-Profil mit `-25000` blockieren. Das ist fragil:
Scores lassen sich durch andere Formate überkompensieren.

**Korrekt:** Eine Auflösung, die nicht im `qualities`-Block des Profils steht,
kann gar nicht erst gegriffen werden. Der Profil-Qualitätsblock **ist** das Gate,
nicht der Score. Scores regeln die Präferenz *innerhalb* des Erlaubten.

---

## Sprach-Semantik (der Kern)

Die entscheidende Präzisierung: **„Deutsch" heißt „Deutsch muss enthalten sein"**,
nicht „ausschließlich Deutsch". Ein Release mit deutscher *und* englischer
Tonspur ist ideal (Originalton). Ein Release ohne Deutsch ist wertlos.

### `languageMode = "required"` (Default)

| Release enthält | Bewertung | Ergebnis |
|-----------------|-----------|----------|
| Deutsch + Englisch | `+11000` (German DL) | ✅ beste Wahl |
| nur Deutsch | `+10000` (German) | ✅ akzeptiert |
| Deutsch + Französisch | `+10000` | ✅ akzeptiert — Zusatzsprachen sind egal |
| nur Englisch | `-1000000` (Not German) | ❌ ausgeschlossen |
| nur Französisch | `-1000000` | ❌ ausgeschlossen |
| nichts Passendes vorhanden | — | ❌ **kein Download** — bewusst |

**Regel:** Die Zielsprache wird positiv bewertet und ihr Fehlen hart
ausgeschlossen. **Andere Sprachen werden nicht bestraft** — sie sind erlaubt,
solange die Zielsprache dabei ist.

### Die Asymmetrie zwischen „de" und „en"

Wichtig für die Umsetzung: TRaSH hat **kein positives „English"-Custom-Format**,
weil Englisch die stillschweigende Grundannahme ist. Daraus folgt:

| Ziel | Positiv-Gate | Ausschluss | `min_format_score` |
|------|--------------|------------|--------------------|
| `de` | `German` +10000, `German DL` +11000 | `Language: Not German` → −1000000 | **10000** |
| `en` | — (keins nötig) | `Language: Not English` → −1000000 | **0** |

Bei `en` erfolgt die Auswahl also rein über den Ausschluss. Deutsch wird dabei
**nicht** bestraft — ein deutsch/englisches Release ist auch für `en` brauchbar.

### Die anderen Modi

| Modus | Verhalten |
|-------|-----------|
| `required` (Default) | wie oben — kein Kompromiss |
| `preferred` | Zielsprache +10000, Fehlen nur −10000 → Fallback möglich |
| `any` | kein Sprach-Scoring |

**Warum `required` der Default ist:** Es entspricht der Erwartung („ich will
deutsche Serien"). Ein Fallback, der ungefragt englische Releases lädt,
überrascht negativ. Wer den Fallback will, schaltet ihn bewusst ein.

---

## Qualitäts-Kette

`quality_sort = "top"` sorgt dafür, dass die Reihenfolge im `qualities`-Block die
Präferenz bestimmt — Scores können sie **nicht** umkehren.

| `preferences.quality` | Profil-Qualitäten (in dieser Reihenfolge) | `until_quality` |
|-----------------------|-------------------------------------------|-----------------|
| `"1080p"` | 1080p → 720p → 540p | 1080p |
| `"2160p"` | 2160p → 1080p → 720p | 2160p |

Was nicht in der Liste steht, wird nie geladen. 4k ist im 1080p-Profil schlicht
**nicht enthalten** — kein negativer Score nötig (siehe Falle 3).

---

## Ableitungen: Was das Modul daraus baut

| Aus | Wird | Wo |
|-----|------|-----|
| `usenet.provider` | SABnzbd-Server-Eintrag inkl. Verbindungen | `525-provision` zur Laufzeit (nicht Nix!) |
| `usenet.indexers` | Prowlarr-Indexer + Sync in die *arr | `525-provision/prowlarr.nix` |
| `preferences.*` | Recyclarr-Profile, Custom-Format-Scores, Quality-Definitionen | `560-recyclarr` |
| `storage.mediaRoot` | Root-Ordner in Sonarr/Radarr/Seerr, Bibliothekspfade in Jellyfin | `525-provision` |
| — | Ports, User, Hardening, Slices, Ingress, mDNS, VPN-Sandbox | automatisch |

---

## Zu `connections`

Der Wert ist ein Tuning-Parameter, kein Korrektheitsparameter:

- Zu wenige → Leitung nicht ausgelastet
- Zu viele → Overhead, kann **langsamer** werden
- Obergrenze setzt der Provider

Faustwerte: bis 100 Mbit ≈ 8–12, darüber ≈ 20–30, Gigabit ≈ 30–50. Das Optimum
ist die *niedrigste* Zahl, die die Leitung auslastet.

**Default `16`** — angeblich seit SABnzbd 5.1.0 auch dessen eigener Default.
⚠️ **Nicht verifiziert**, vor der Umsetzung gegen die SABnzbd-Doku prüfen.

---

## Umsetzungsreihenfolge

| # | Schritt | Anmerkung |
|---|---------|-----------|
| 1 | `usenet`- und `preferences`-Optionen in `default.nix` | reine Options-Arbeit |
| 2 | `preset`-Option | setzt Einzelschalter per `mkDefault` |
| 3 | SABnzbd-Server aus `usenet.provider` — **zur Laufzeit** | erweitert `525-provision`, nicht `530-sabnzbd` |
| 4 | Prowlarr-Indexer aus `usenet.indexers` | `525-provision/prowlarr.nix` liest bereits eine Indexer-Liste |
| 5 | Recyclarr-Profile aus `preferences` generieren | größter Brocken; trash_ids vorher verifizieren |
| 6 | README auf die Glühbirnen-API umstellen | Quickstart = das Beispiel oben |

Schritt 3 ist bewusst in der Provisionierung, nicht im SABnzbd-Modul: Nur dort
können Zugangsdaten zur Laufzeit gelesen werden, ohne im Store zu landen.

---

## Konsequenzen

**Positiv**
- Neuer Nutzer schreibt ~12 Zeilen statt 50+ Optionen zu verstehen.
- Sprache/Qualität sind erstmals echte Optionen statt hart verdrahteter Profile.
- Die Pflichtangaben sind genau die, die das Modul nicht wissen *kann*.

**Negativ**
- `560-recyclarr` wird deutlich komplexer (Profil-Generierung statt statischer Config).
- Die trash_id-Pflege wird zur Daueraufgabe — TRaSH ändert IDs und Scores.
- `preset` erzeugt eine zweite Ebene neben den Einzelschaltern; die
  `mkDefault`-Semantik muss sauber dokumentiert sein, sonst wirkt es magisch.

**Offene Fragen**
1. Mehrere Provider (Backup-Server mit niedrigerer Priorität)? Die Option ist als
   Liste erweiterbar angelegt, aber Priorität/Failover ist ungeklärt.
2. Getrennte Präferenzen für Filme und Serien (4k-Filme, 1080p-Serien)?
   Aktuell eine globale Einstellung.
3. Wie kommen die trash_ids ins Repo — vendored oder zur Bauzeit geholt?
