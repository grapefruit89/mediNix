# ---
# id: 5042
# title: "Pfadisomorphie — was aus der Nummer folgt und was nicht"
# status: "accepted"
# date: "2026-07-20"
# related: [5040, 11]
# tags: ["registry", "ports", "uid", "isomorphie", "ssot", "imports"]
# error_pattern: "registry|isomorph|port.*ableit|mediaGid"
# ---

# ADR-5042 — Pfadisomorphie

## Herkunft

Grundlage ist ein Konzeptdokument (`Nix-Grok_50-media_Pfadisomorphie_Konzept.md`),
entstanden aus einem Brainstorm mit DeepSeek, anschließend kritisch überarbeitet.
Es ist deutlich sorgfältiger als vergleichbare KI-Vorlagen: es markiert eigene
Fehler früherer Iterationen, kennzeichnet Ungeprüftes als ungeprüft und begründet
Verworfenes. Dieses ADR übernimmt einen Teil davon, lehnt einen anderen begründet
ab und ergänzt, was die Messung auf echter Hardware ergeben hat.

## Das Problem

Für **einen** neuen Dienst mussten **sieben** Stellen angefasst werden:

| # | Wo | Was |
|---|---|---|
| 1 | `default.nix` | Import |
| 2 | `default.nix` | `enable`-Option |
| 3 | `default.nix` | Port |
| 4 | `lib/service-tiers.nix` | Tier |
| 5 | `500-media-ingress/mdns.nix` | Namensliste |
| 6 | `500-media-ingress/default.nix` | Dienst-Map |
| 7 | — | der Ordner |

Fünf davon waren **dieselbe Information, fünfmal geschrieben**. Jede Abweichung
war ein stiller Fehler: ein Dienst, den jemand in der mDNS-Liste vergisst, läuft,
hat einen Port und einen vHost — ist aber unter `{name}.local` **unauffindbar**,
ohne jede Fehlermeldung.

## Entscheidung

**Eine Tabelle in `lib/registry.nix`. Aus ihr folgt alles Ableitbare.**

Danach sind es **zwei** Handgriffe: eine Zeile in der Registry, plus der Ordner.

### Was abgeleitet wird

| Ableitung | Regel | Beispiel Sonarr (512) |
|---|---|---|
| **Port** | Nummer × 10 | 5120 |
| **UID** | 1000 + Nummer | 1512 |
| **Tier** | Feld in der Registry | `backend-lan` |
| **mDNS-Menge** | alle mit `ui = true` | `sonarr.local` |
| **Ingress-Map** | dieselbe Menge | vHost |

### Was **nicht** abgeleitet wird — und warum

| Bleibt | Statt |
|---|---|
| `sonarr.service` | `media-512.service` |
| `/var/lib/sonarr` | `/var/lib/media-512` |
| `sonarr.local` | `sonarr.media.local` |

Das ist der Punkt, an dem dieses ADR vom Konzeptdokument abweicht. Zwei Gründe:

**Erstens, technisch.** nixpkgs verdrahtet den Namen fest:

```nix
# nixos/modules/services/misc/servarr/sonarr.nix
systemd.services.sonarr = { ... };      # Zeile 73
StateDirectory = "sonarr";              # Zeile 125
```

Um daraus `media-512` zu machen, müsste man das nixpkgs-Modul entweder **nicht
benutzen** und die Unit selbst pflegen (ExecStart, User, StateDirectory,
Update-Mechanik — für jeden der zehn Dienste, über nixpkgs-Versionen hinweg),
oder eine **Alias-Unit** danebenlegen (zwei Namen für dasselbe — genau die
Doppeldeutigkeit, die Isomorphie beseitigen soll). Beides ist dauerhafter
Aufwand gegen den Strom.

**Zweitens, inhaltlich.** Das entscheidende Kriterium lautet:

> **Ersetzt die Ableitung etwas Willkürliches oder etwas Bedeutungsvolles?**

Ports und UIDs sind ohnehin bedeutungslose Zahlen. `8989` muss man nachschlagen,
`5120` nicht — **reiner Gewinn**. Unit-Namen und Pfade sind bereits sprechend;
eine Zahl ersetzt dort keine Zahl, sondern **Information**.

Konkret am selben Tag erlebt: Als Sonarr nicht startete, lautete die
entscheidende Zeile

```
SonarrStartupException: AppFolder /var/lib/sonarr is not writable
```

Mit Nummernschema hätte dort `/var/lib/media-512` gestanden — und man hätte erst
nachschlagen müssen, welcher Dienst 512 ist. Bei jeder Fehlersuche, bei jedem
`journalctl -u`, bei jeder fremden Foren-Hilfe.

### Nummernschema

> **X0 ist immer Block-ID, nie ein Dienst. X1–X9 sind Dienste.**

Blockreihenfolge folgt dem Weg einer Anfrage durch den Stack:

```
500 ingress · 510 acquisition · 520 download · 530 management
540 playback · 550 access · 560 observability · 590 security
```

Keine reservierten Lücken — eine Lücke sieht aus wie ein Versehen.

Die Exporter bekamen **eigene Nummern** (561–564) statt eines Sammeleintrags.
Ein gemeinsamer Basisport plus Versatz wäre wieder eine Nebenrechnung gewesen,
und genau die soll das Schema abschaffen.

## Die GID — die eine bewusste Ausnahme

**Der stärkste Punkt des Konzeptdokuments.**

Wäre die GID isomorph (`1000 + Nummer`), bekäme jeder Dienst seine **eigene**
Gruppe. Sonarr schriebe mit GID 1512, Jellyfin wollte mit 1541 lesen —
`Permission denied`. Das ist der klassische Docker-PUID/PGID-Fehler in Nix-Form.

Der gesamte Sinn des *arr-Musters ist eine **gemeinsame** Gruppe für alle
Dienste am selben Bibliothekspfad.

```
UID ist isomorph.  GID ist bewusst fix.
```

**Warum fix und nicht automatisch:** NixOS legt automatisch vergebene Zuordnungen
unter `/var/lib/nixos` ab. Bei Impermanence mit tmpfs-Wurzel verschwindet das beim
Neustart, wenn es nicht persistiert wird — die Gruppe bekäme eine neue GID, und
bestehende Dateien gehörten plötzlich niemandem.

Auf q958 gemessen: die GID war **990**, automatisch vergeben. Also genau dieser
Fall. Festgelegt auf **3000**, weil `< 1000` bei NixOS für Systemkonten reserviert
ist und `1000` auf den meisten Systemen der erste echte Benutzer.

## Automatische Imports — und eine widerlegte Prämisse

Ordner mit dreistelliger Nummer werden automatisch eingebunden. Damit fällt die
siebte Stelle weg.

Ein zweites Brainstorm-Dokument begründete das mit der **Reihenfolge**: Nix-Imports
seien reihenfolgeabhängig, spätere Module überschrieben frühere, und die Nummern
lösten das durch Sortierung.

**Empirisch widerlegt.** Test mit zwei Modulen, die `networking.hostName`
unterschiedlich setzen, in beiden Reihenfolgen:

```
Reihenfolge A,B  →  Fehler: "BBB" und "AAA" kollidieren
Reihenfolge B,A  →  Fehler: "AAA" und "BBB" kollidieren
```

**Das NixOS-Modulsystem ist reihenfolgeunabhängig.** Bei gleicher Priorität gibt
es einen Konflikt, kein „letzter gewinnt". Vorrang regeln ausschließlich
`mkForce`, `mkDefault` und `mkOverride`.

Das macht Auto-Import **sicherer** als angenommen. Sortiert wird trotzdem — nicht
für die Auswertung, sondern damit Fehlermeldungen in nachvollziehbarer Reihenfolge
erscheinen.

**Eine Regel war dafür nötig:** Der Scan erfasst nur **Ordner**, nie Einzeldateien.
`520-arr-stack` hing vorher mit zwei Dateien an der obersten Ebene, während
`500-media-ingress` und `525-provision` ihre Dateien selbst einbinden. Diese
Inkonsistenz hätte der Scan stillschweigend verschluckt. Jetzt gilt: **was in
einem Ordner liegt, bindet dessen `default.nix` ein.**

## Abgelehnt

| Vorschlag | Grund |
|---|---|
| Unit-Namen `media-NNN.service` | siehe oben — kämpft gegen nixpkgs, ersetzt Namen durch Zahlen |
| State-Pfade `/var/lib/media-NNN` | dito |
| DNS `{name}.media.local` | die heute funktionierende mDNS-Auflösung bricht ohne Gegenwert |
| `grapefruitMedia` → `my.media.*` umbenennen | **Missverständnis.** `grapefruitMedia` ist kein Platzhalter, sondern bewusst gewählt, damit mediNix **kein** `my.*` braucht — das ist Nix-Grok-spezifisch. Die Umbenennung würde die Portabilität rückgängig machen (Issue #19, ADR-5040) |
| Registry referenziert `config.my.uids.mediaGroup` | dieselbe Kopplung. Die GID steht als Konstante in der Registry |
| Zweiter Registry-Entwurf | älterer Stand: `jellyfin = 510` (der Pipeline-Fehler, den das erste Dokument selbst korrigiert), und `deriveUid = number` ergäbe UIDs 500–591, also im **reservierten Systembereich** |
| API-Key-Präfix nach Schema | war schon im Konzeptdokument verworfen — senkt die Entropie des Secrets ohne Gegenwert |

## Nachweis

Auf q958 mit allen zehn Diensten:

```
prowlarr 5110 · sonarr 5120 · radarr 5130 · lidarr 5140 · readarr 5150
sabnzbd 5210 · jellyfin 5410 · audiobookshelf 5420 · navidrome 5430
```

12 Units aktiv, keine Ausfälle, 9 von 10 über `{service}.local` erreichbar
(Jellyfin blockiert weiterhin der Upstream-Bug, siehe LEARNINGS L6).

Für die Schritte, die **kein** Verhalten ändern sollten (Tier-Weiterleitung,
mDNS-Menge, Auto-Import), ist der Store-Pfad der Prüfkonfiguration vor und nach
der Änderung **identisch** — bitgleiches Ergebnis.

## Ein Einwand, der berechtigt war

Meine erste Einschätzung gegen die Portumnummerierung lautete: „jedes Lesezeichen,
jede Client-Konfiguration bricht". Der Repo-Eigentümer widersprach: das Projekt ist
in der Entwicklungsphase, es gibt keine Nutzer, keine gewachsenen Konfigurationen,
keine Daten.

**Er hatte recht.** Das war ein Produktivsystem-Argument, das hier nicht gilt. Die
Umstellung kostete faktisch nichts — später hätte sie echten Schmerz bedeutet.

> **Lehre:** Ein Kostenargument braucht den Zeitpunkt dazu. Dieselbe Änderung ist
> in der Entwicklungsphase billig und im Betrieb teuer. Wer das nicht trennt,
> blockiert richtige Entscheidungen mit Gründen, die noch nicht gelten.
