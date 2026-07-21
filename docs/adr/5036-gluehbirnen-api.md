# ---
# id: 5036
# title: "Glühbirnen-API: die minimale Pflichtkonfiguration"
# status: "accepted"
# note: "Entwurf, noch nicht gebaut"
# date: "2026-07-18"
# related: [5035, 5037]
# tags: ["api", "optionen", "profil", "katalog", "defaults", "kiss"]
# error_pattern: "gluehbirne|glühbirne|pflichtkonfiguration|minimale.*konfig|profil.*sprache"
# ---

# ADR-5036 — Glühbirnen-API: die minimale Pflichtkonfiguration

**Betrifft:** `default.nix`, `530-sabnzbd/`, `560-recyclarr/`, `525-provision/`

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

  # ── 1. Usenet-Zugang ── nur Zugangsdaten, Rest aus dem Katalog ──
  usenet.provider = {
    preset = "eweka";                        # Host/Port/SSL/Limits vorbelegt
    usernameFile = "/run/secrets/usenet-user";
    passwordFile = "/run/secrets/usenet-pass";
  };

  # ── 2. Indexer ── nur der API-Key, URL aus dem Katalog ──
  usenet.indexers = [
    { preset = "nzbgeek"; apiKeyFile = "/run/secrets/nzbgeek-key"; }
  ];

  # ── 3. Präferenzen (bestimmt die Profile) ──
  preferences = {
    # Profile, die in Sonarr UND Radarr angelegt werden.
    # Pro Serie/Film wird eines davon gewählt -- so arbeiten die *arr.
    profiles = [
      { id = "de"; languages = [ "de" ]; default = true; }
      { id = "en"; languages = [ "en" ]; }
    ];
    # Qualität getrennt je App -- Serien und Filme dürfen sich unterscheiden.
    quality = {
      series = "1080p";
      movies = "1080p";              # z.B. "2160p" für 4k-Filme
    };
  };

  # ── 4. Storage (Default vorhanden) ──
  storage.mediaRoot = "/data";

  # ── 5. Dienste (Preset statt Einzelschalter) ──
  preset = "usenet-media";
};
```

**Das ist die vollständige Konfiguration.** Zehn Zeilen, davon vier reine
Dateipfade zu Secrets. Alles andere hat Defaults.

Wer einen Provider oder Indexer nutzt, der nicht im Katalog steht, gibt die
Felder weiterhin manuell an (siehe „Kataloge" unten) — der Katalog ist eine
Abkürzung, keine Einschränkung.

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

### 3. „Recyclarr hat doch eine `language`-Option" — hat es nicht

Ein wiederkehrender Vorschlag lautet, das ganze Score-Gating durch eine simple
Whitelist zu ersetzen:

```yaml
quality_profiles:
  - name: "German 1080p"
    language: ["german", "english"]   # ❌ EXISTIERT NICHT
```

**Geprüft am Recyclarr-Schema** (`schemas/config/quality-profiles.json`,
abgerufen 2026-07-18). Erlaubt sind ausschließlich:

`trash_id` · `name` · `reset_unmatched_scores` · `score_set` · `upgrade` ·
`min_format_score` · `min_upgrade_format_score` · `quality_sort` · `qualities`

Das Schema setzt **`additionalProperties: false`**. Eine Config mit `language:`
wird also nicht etwa ignoriert — sie **schlägt bei der Validierung fehl**.

**Warum es das nicht gibt:** Sonarr v4 hat die Language-Profiles entfernt, Radarr
hat Sprache aus den Quality-Profiles herausgenommen. Beide behandeln Sprache
heute ausschließlich über Custom Formats. Genau deshalb macht TRaSH das
Sprach-Gating über CF-Scores — nicht aus Vorliebe fürs Frickeln, sondern weil es
der einzige verfügbare Weg ist. Der Vorschlag beschreibt Sonarr **v3**.

**Merke:** Das Score-Gating unten ist kein Umweg. Es ist der Weg.

### 4. Größenangaben sind MB/min, nicht GB/Stunde

Ebenfalls aus demselben Vorschlag:

```yaml
- name: "WEBDL-1080p"
  max: 75        # ❌ Kommentar sagte "75 GB pro Stunde"
```

Quality-Definitionen in Radarr/Sonarr sind **MB pro Minute**. 75 MB/min sind rund
**4,5 GB/Stunde**, nicht 75. Eine Nutzeroption `maxSize = 75` mit der Bedeutung
„GB" würde die Limits um Faktor ~800 verfehlen und praktisch jedes Release
durchlassen oder blockieren.

Wenn eine Größenoption angeboten wird, dann mit **expliziter Einheit im Namen**
(`maxSizeMbPerMin`) — oder gar nicht, und stattdessen die TRaSH-Definitionen
übernehmen.

### 5. Auflösungen über negative Scores ausschließen

Der Entwurf wollte 4k im 1080p-Profil mit `-25000` blockieren. Das ist fragil:
Scores lassen sich durch andere Formate überkompensieren.

**Korrekt:** Eine Auflösung, die nicht im `qualities`-Block des Profils steht,
kann gar nicht erst gegriffen werden. Der Profil-Qualitätsblock **ist** das Gate,
nicht der Score. Scores regeln die Präferenz *innerhalb* des Erlaubten.

---

## Mehrere Profile statt einer globalen Sprache

**Der reale Anwendungsfall:** Eine Person im Haushalt schaut deutsche Releases,
eine andere gelegentlich englische. Das ist **kein** „Deutsch oder Englisch, egal
was kommt" — es sind **zwei getrennte Profile**, zwischen denen pro Titel gewählt
wird.

Das passt exakt zur Arbeitsweise der *arr: **Das Quality-Profile hängt am
einzelnen Titel**, nicht global an der Instanz. Eine deutsche Serie bekommt das
deutsche Profil, ihre englische Serie das englische. Jellyseerr setzt beim
Anlegen das Default-Profil, überschreibbar pro Anfrage.

```nix
preferences.profiles = [
  { id = "de"; languages = [ "de" ]; default = true; }
  { id = "en"; languages = [ "en" ]; }
];
```

| Feld | Bedeutung |
|------|-----------|
| `id` | Kurzname, geht in den Profilnamen ein (`German 1080p`) |
| `languages` | Liste — **mindestens eine** davon muss im Release enthalten sein |
| `default` | Profil für neu angelegte Titel und als Seerr-Vorgabe; genau eines muss `true` sein |

`languages` ist bewusst eine **Liste**: Wer beide Sprachen gleichwertig
akzeptiert, schreibt `languages = [ "de" "en" ]` und bekommt ein Profil. Wer sie
getrennt haben will, legt zwei Profile an. Beides ist ausdrückbar.

### Qualität getrennt je App

Sonarr und Radarr haben **eigene, unabhängige Quality-Profiles**. Deshalb ist die
Auflösung keine Eigenschaft des Sprachprofils, sondern der App:

```nix
preferences.quality = { series = "1080p"; movies = "2160p"; };
```

Damit ist „4k-Filme, aber 1080p-Serien" ohne Sonderfall abgedeckt. Die Profile
heißen dann `German 1080p` in Sonarr und `German 2160p` in Radarr.

### Idee für später (ungeprüft)

Jellyseerr kann Nutzern unterschiedliche Default-Profile zuweisen. Damit würde
ihr Seerr-Konto automatisch auf das englische Profil zeigen, ohne dass jemand
etwas auswählen muss. ⚠️ Ob und ab welcher Version das geht: **nicht verifiziert**
— vor einer Zusage gegen die Seerr-Doku prüfen.

---

## Sprach-Semantik pro Profil

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

| `preferences.quality` | Kette (Reihenfolge = Präferenz) | `until_quality` |
|-----------------------|----------------------------------|-----------------|
| `"1080p"` | **1080p → 720p → 540p → 480p** | 1080p |
| `"2160p"` | **2160p → 1080p → 720p → 540p → 480p** | 2160p |

Die Kette ist absteigend vollständig: Lieber eine schlechtere Auflösung als gar
nichts — aber **nur**, wenn nichts Besseres existiert. Sobald später ein besseres
Release auftaucht, greift `upgrade.allowed` und ersetzt es bis `until_quality`.

**4k ist im 1080p-Profil schlicht nicht enthalten** — kein negativer Score nötig.
Umgekehrt enthält das 4k-Profil 1080p und darunter als Rückfall, weil ein
1080p-Release besser ist als kein Film.

Was nicht in der Liste steht, wird nie geladen (siehe Falle 3).

---

## Kataloge statt Freitext

Der Nutzer soll den API-Key eingeben — nicht die Endpunkt-URL nachschlagen.
Deshalb bringt das Modul zwei Kataloge mit.

### Warum `enum` das Nix-Äquivalent zum Dropdown ist

Ein `types.enum [ "nzbgeek" "drunkenslug" … ]` liefert genau das, was ein
Dropdown im Web leistet: begrenzte Auswahl, Tab-Completion in der Editor-
Integration, und — der eigentliche Gewinn — **Validierung zur Bauzeit**. Ein
Tippfehler bricht den Build mit einer Liste der gültigen Werte, statt zur
Laufzeit einen kaputten Indexer zu erzeugen.

### `lib/usenet-catalog.nix`

```nix
{
  providers = {
    eweka      = { host = "news.eweka.nl";       port = 563; ssl = true; maxConnections = 50; };
    newshosting= { host = "news.newshosting.com"; port = 563; ssl = true; maxConnections = 100; };
    # …
  };

  indexers = {
    nzbgeek     = { baseUrl = "https://api.nzbgeek.info"; implementation = "Newznab";
                    configContract = "NewznabSettings"; protocol = "usenet"; };
    drunkenslug = { baseUrl = "…"; … };
    # …
  };
}
```

### Verwendung

```nix

> **Hinweis (2026-07-21):** Die unten beschriebenen Dateien unter `lib/`
> (`recyclarr-formats.nix`, `recyclarr-scoring.nix`, `ingress-lib.nix`,
> `usenet-catalog.nix`) sind **NOCH NICHT UMGESETZT**. Dieses ADR beschreibt
> einen Entwurf, kein vorhandenes Verzeichnis — wer die Dateien sucht, findet
> sie nicht, und das ist kein Fehler.

# Katalog-Eintrag: nur Zugangsdaten nötig
usenet.provider = {
  preset = "eweka";
  usernameFile = "…"; passwordFile = "…";
};

# Katalog + Übersteuerung einzelner Felder
usenet.provider = {
  preset = "eweka";
  connections = 30;            # überschreibt den Katalog-Default
  usernameFile = "…"; passwordFile = "…";
};

# Ohne Katalog — vollständig manuell
usenet.provider = {
  host = "news.example.com"; port = 563; ssl = true;
  usernameFile = "…"; passwordFile = "…";
};
```

**Auflösungsregel:** explizit gesetztes Feld > Katalog-Eintrag > Modul-Default.
Umgesetzt über `lib.mkDefault` auf den Katalogwerten, damit der Nutzer jedes Feld
einzeln überstimmen kann, ohne den Preset aufzugeben.

**Assertion:** Entweder `preset` **oder** `host` muss gesetzt sein — beides
gleichzeitig ist erlaubt (Preset + Übersteuerung), keines von beidem bricht den
Build mit klarer Meldung.

### ⚠ Katalogdaten sind zu verifizieren

Die oben genannten Hostnamen, Ports und Verbindungslimits sind **Platzhalter aus
allgemeiner Kenntnis und ungeprüft**. Sie stehen hier, um die *Struktur* zu
zeigen.

Vor der Umsetzung: jeden Eintrag gegen die offizielle Doku des jeweiligen
Anbieters prüfen und mit Datum vermerken. Ein falscher Hostname im Katalog ist
schlimmer als gar kein Katalog — der Nutzer vertraut ihm.

Gleiches gilt für die Indexer-`baseUrl`: Newznab-Endpunkte unterscheiden sich
teils von der Website-Domain. Quelle ist die API-Seite des jeweiligen Indexers,
nicht das Gedächtnis (AGENTS.md Regel 0).

**Pflege-Realität:** Ein Katalog veraltet. Deshalb bleibt der manuelle Weg
gleichwertig unterstützt, und der Katalog ist bewusst klein — nur die
verbreitetsten Anbieter, nicht der Anspruch auf Vollständigkeit.

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
2. ~~Getrennte Präferenzen für Filme und Serien?~~ **Gelöst** — `quality.series`
   und `quality.movies` getrennt, weil Sonarr und Radarr ohnehin eigene
   Quality-Profiles führen.
3. Wie kommen die trash_ids ins Repo — vendored oder zur Bauzeit geholt?
4. Können Profile pro App unterschiedlich sein (z.B. englisches Profil nur in
   Radarr, nicht in Sonarr)? Aktuell werden alle Profile in beiden Apps angelegt.
   Das ist harmlos (ungenutzte Profile stören nicht), aber ggf. unsauber.
5. Jellyseerr-Nutzer automatisch auf ein Default-Profil mappen — verfügbar?
