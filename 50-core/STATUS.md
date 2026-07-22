# STATUS — Lagekarte mediNix

**Stand:** 2026-07-21, abends
**Zweck:** Überblick behalten. Was steht, was wackelt, wo als Nächstes anfassen.

> Einstiegspunkt, wenn der Faden gerissen ist. Ersetzt keine Issues — sagt, in
> welcher Reihenfolge man sie ansieht.
>
> **Diese Datei ist eine Momentaufnahme, keine Wahrheitsquelle.** Widerspricht
> sie dem, was `systemctl` und `curl` gerade zeigen, haben die Befehle recht.
> Der Pflichtlauf steht in `50-core/RUNBOOK.md`, Abschnitt 0.

---

## Was nachweislich läuft

Geprüft am 2026-07-21 von außen über `.local`, nicht über `127.0.0.1`.

| Dienst | Nr. | Port | HTTP | Bemerkung |
|---|---|---|---|---|
| Caddy | 501 | 80 | — | Einzelfehlerpunkt, gegen OOM geschützt |
| Prowlarr | 511 | 5110 | 302 | |
| Sonarr | 512 | 5120 | 302 | |
| Radarr | 513 | 5130 | 302 | |
| Lidarr | 514 | 5140 | 302 | |
| Readarr | 515 | 5150 | 302 | |
| SABnzbd | 521 | 5210 | 303 | lädt nicht — Platzhalter-Zugangsdaten |
| **Jellyfin** | 541 | 5410 | **302** | **seit heute, 0 Neustarts** |
| Audiobookshelf | 542 | 5420 | 200 | |
| Navidrome | 543 | 5430 | 302 | |
| Feishin | 544 | — | 200 | statisch, kein Prozess |
| Jellyseerr | 551 | 5510 | 307 | |

**11 von 11 antworten. 0 failed units. System bootfest.**

Ports folgen der Registry: Ordnernummer × 10. Wer einen Port von Hand pflegt,
hat `lib/registry.nix` umgangen.

---

## Was sich seit dem letzten Stand geändert hat

| | |
|---|---|
| **Jellyfin läuft** | Ursache waren vorab eingespielte Configs, nicht die Version. Der Downgrade auf 10.10.7 war wirkungslos und ist entfernt |
| **Registry** | `lib/registry.nix` ersetzt fünf handgepflegte Stellen |
| **Agenten-Doku** | `CLAUDE.md`, `.claude/rules/`, je Modulordner eine Datei |
| **Linting** | `nixfmt` statt `nixfmt-rfc-style` (Alias mit Warnung), `nixf-diagnose` und `shellcheck` dazu |
| **devNIX** | neues Repo — Werkzeuge als NixOS-Modul plus Claude-Plugin mit Hooks |
| **Altlasten** | fünf überholte Review-Dokumente nach `50-core/archiv/` |

---

## Was wackelt

| Was | Zustand | Nächster Schritt |
|---|---|---|
| **Keine Regressionstests** | `checks/` evaluiert nur, startet nichts | Issue #48: `nixosTest`. **Die wichtigste offene Aufgabe** |
| `registry.uids`, `mediaGid` | **verdrahtet** (wireFixedUids) | auf q958 aktiv: Sonarr 5320, media-GID 5000 — impermanence-fest |
| `exporters.enable = true` | erzeugt weder Units noch Ports | **ungeklärt.** Erste Schritte im Runbook, Abschnitt 11 |

---

## Bewusst offen — kein Fehler

Wer das „repariert", arbeitet an einem Phantom.

| Was | Warum |
|---|---|
| SABnzbd lädt nichts | Platzhalter-Zugangsdaten. Secrets gehören nicht ins Repo |
| `usenet-confinement` inaktiv | kein WireGuard-Schlüssel hinterlegt |
| `provision` inaktiv | keine API-Schlüssel |
| `recyclarr` aus | `trash_ids` ungeprüft — falsche IDs zerlegen still die Qualitätsprofile |

---

## Reihenfolge für die nächste Sitzung

1. **`nixosTest`** (#48) — solange kein Test fehlschlägt, wenn jemand einen
   Stand bricht, geht jeder erreichte Stand still verloren. Alles andere ist
   danach billiger.
2. `registry.uids` verdrahten — oder die Option streichen. Berechnet und
   unbenutzt ist der schlechteste Zustand: sie sieht erledigt aus.
3. `exporters` klären.

> **Eine Front zur Zeit.** Fünf Stufen hoch in einer Sache fühlen sich wie
> Rückschritt an, wenn vier andere offen stehen. Begründung in
> `.claude/rules/arbeitsweise.md`.

---

## Wo was steht

| Frage | Datei |
|---|---|
| Neue Maschine einrichten | `50-core/ONBOARDING.md` |
| Wie hängt alles zusammen | `50-core/ARCHITEKTUR.md` |
| Etwas ist kaputt | `50-core/RUNBOOK.md` |
| Port, UID, Tier, mDNS | `lib/registry.nix` |
| Warum so entschieden | `50-core/adr/` |
| Was schiefging | `LEARNINGS.md` |
| Historische Begründungen | `50-core/archiv/` — kein Zielzustand mehr |
