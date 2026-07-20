# AGENTS.md — verbindliche Regeln für alle Agenten in diesem Repo

Gilt für jeden KI-Agenten (Claude, Grok, Gemini, Copilot …) und jeden Menschen,
der hier arbeitet. Lies das **vor** der ersten Änderung.

---

## Regel −1 — Git: ausschließlich `main`. Keine Branches. Ausnahmslos.

**Es gibt genau einen Branch: `main`.** Nicht „bevorzugt", nicht „meistens" —
ausschließlich.

Verboten, auch wenn es fachlich sinnvoll erscheint:

- `git checkout -b`, `git switch -c` — kein Feature-Branch, kein Fix-Branch,
  kein `wip/`
- Pull Requests als Arbeitsweise. **Issues und Discussions sind ausdrücklich
  erwünscht** — dieses Repo ist als Ideen- und Diskussionsraum gedacht. PRs nicht.
- Vorschläge wie „lass uns das auf einem Branch ausprobieren"

**Begründung — nicht technisch, sondern menschlich:** Der Mensch, dem dieses
Repo gehört, verliert bei mehreren Branches den Überblick. Ein Agent, der einen
Branch anlegt, erzeugt genau die Verwirrung, die diese Regel verhindern soll.
Der technische Vorteil ist hier kleiner als der Schaden.

**Stattdessen:**

| Situation | Vorgehen |
|-----------|----------|
| Änderung ist riskant | Erst Dry-Build, dann committen |
| Änderung ist unfertig | Nicht committen — im Arbeitsverzeichnis liegen lassen |
| Etwas ausprobieren | Kopie unter `/tmp`, nicht im Repo |
| Rückgängig machen | `git revert` — neuer Commit auf `main` |
| Alten Stand ansehen | `git show <sha>:<pfad>` — kein Auschecken |

Bereits existierende Branches: stehen lassen, nicht darauf arbeiten, nicht
davon abzweigen. Nur `main` ist die Wahrheit.

---

## Regel 0 — Originalquellen. Immer. Ausnahmslos.

**Niemals eine API, eine Option, einen Paketnamen oder ein Schema aus dem
Gedächtnis nennen. Immer die Primärquelle anzapfen.**

Das ist keine Stilfrage. Trainingsdaten sind Monate bis Jahre alt, API-Schemata
ändern sich zwischen Versionen, und Optionsnamen in nixpkgs werden umbenannt.
Eine falsch erinnerte Feldbezeichnung fällt nicht beim Bauen auf, sondern
Wochen später beim ersten echten Download.

| Frage | Pflichtquelle |
|-------|---------------|
| *arr-/Prowlarr-API, Felder, Endpunkte | OpenAPI-Spec **und** die laufende Instanz — siehe `docs/api-reference.md` |
| nixpkgs-Paket, `services.*`-Option | nixos-MCP (live), nicht das Gedächtnis |
| `lib.*` / `builtins.*` | Noogle — Argumentreihenfolge ändert sich zwischen Versionen |
| Caddy, systemd, Jellyfin-API, externe Libs | Context7 / offizielle Doku |
| Fehler aus einem Fremdpaket | GitHub-Issues des Projekts, bevor debuggt wird |

**„Ich weiß das aus dem Training" ist kein gültiger Grund.** Ein MCP-Call kostet
Sekunden, eine falsche Annahme kostet Stunden.

### Wenn eine Quelle nicht vollständig abrufbar ist

Kommt es vor — große OpenAPI-Specs laufen in Größen- oder Zeitlimits. Dann gilt:

1. **Nicht raten und weitermachen.** Kennzeichnen, was verifiziert ist und was nicht.
2. Den Verifikationsstand **dokumentieren** (siehe `docs/api-reference.md`,
   Abschnitt 2 — Tabelle mit ✅ / ⚠️ / ❌ je Quelle).
3. Ein Verfahren hinterlassen, mit dem die offene Stelle später geprüft werden
   kann (dort Abschnitt 8).

Eine ehrlich markierte Lücke ist brauchbar. Eine unmarkierte Vermutung ist gefährlich.

### Quell-URLs sind Architektur, kein Kommentar-Ballast

Die Primärquellen-URLs in `docs/api-reference.md` (Abschnitt 1) und in den
Code-Kommentaren **dürfen bei Refactorings nicht entfernt werden**. Wer sie
löscht, nimmt dem nächsten Bearbeiter die Möglichkeit zu verifizieren — und
zwingt ihn damit zum Raten.

---

## Regel 1 — Verifizieren statt erinnern

Jede erinnerte Zusammenfassung einer früheren Sitzung ist **ein Hinweis, was zu
prüfen ist** — niemals aktueller Wahrheitsstand. Vor jeder Annahme über den
Zustand des Repos: nachsehen.

Konkret hat das in diesem Repo schon mehrfach Arbeit gespart: Mehrere
AI-Reviews behaupteten Lücken (`with lib;`, fehlende Meta-Header, tote
Recyclarr-Optionen, fehlender `AF_NETLINK`-Fix), die längst geschlossen waren.
Wer das ungeprüft übernimmt, arbeitet an Phantom-Problemen.

---

## Regel 2 — Wir sind das Architekturbüro

**Hier wird entworfen, nicht gebaut.** Es gibt in dieser Umgebung kein Nix, keine
Evaluation, keinen Dry-Build. Fehler werden später auf dem echten System
gefunden und behoben.

Daraus folgt der Auftrag: **Den Leuten, die bauen, so viel Denkarbeit wie möglich
abnehmen.** Ein Entwurf ist fertig, wenn er mechanisch umsetzbar ist — mit
konkreten Signaturen, Migrationstabellen, benannten Fallstricken und einer
Reihenfolge. Nicht, wenn die Idee klar ist.

Was das *nicht* heißt: Sorgfalt sparen. Gerade weil hier nichts kompiliert,
muss der Entwurf präziser sein als üblich.

---

## Regel 3 — Portabilität ist der Existenzgrund

mediNix ist der aus dem Host-Repo herausgelöste Media-Stack. Alles, was das
Modul an ein bestimmtes System bindet, ist ein Fehler:

- **Keine** `my.*`-Referenz im portablen Kern (nur `compat-my.nix`, die nicht
  Teil des Flake-Exports ist)
- **Keine** festen IPs, Domains, Interface-Namen, Subnetze
- **Keine** hartkodierten Pfade — alles über Optionen, Defaults abgeleitet
- **Keine** duplizierten nixpkgs-Defaults (siehe `package`-Optionen: `nullOr`
  mit `null`, damit upstream die Wahrheit bleibt)
- `lib.mkDefault` statt `mkForce` auf allem, was der Host setzen können soll

---

## Regel 4 — Sicherheitsdefaults sind fail-closed

Ein stiller Default, der im Fehlerfall „irgendwie funktioniert", ist schlimmer
als gar keiner — der Fehler wird nie sichtbar.

Beispiel aus diesem Repo: `vpn.dns` stand auf `1.1.1.1`. Wer den VPN-Resolver
vergaß, bekam trotzdem funktionierendes DNS — nur eben am Tunnel vorbei.
Heute: Default `[ ]` plus Assertion, die den Build abbricht.

Ebenso: Secrets nur als **Dateipfade**, nie als Env-Wert oder Argument (landen
sonst in `/proc/<pid>/environ` und in der Prozessliste).

---

## Regel 5 — systemd besitzt Lebenszyklus und Orchestrierung

Reihenfolge, Wiederholung, Teilerfolge und Sichtbarkeit macht systemd — nicht
ein selbstgeschriebener Orchestrator. Deshalb acht getrennte oneshot-Units in
der Provisionierung statt eines Über-Skripts (Begründung in ADR-5035).

Eigener Code nur als **„Surgical Glue"** dort, wo Nix und systemd nicht
hinreichen. Und dann: nur stdlib, keine externen Abhängigkeiten.

---

## Wo die Wahrheit liegt

| Thema | Datei |
|-------|-------|
| Naming / DNS / Ingress — Zielzustand | `grok-review.md` |
| Erreichbarkeit LAN/WAN/VPN, TLS | `docs/network-topology.md` |
| API-Endpunkte + Verifikationsstand | `docs/api-reference.md` |
| Provisionierungs-Architektur | `docs/adr/5035-provision-driver-architecture.md` |
| DNS-Tier-Zuordnung (SSoT) | `lib/service-tiers.nix` |
| Optionen-Referenz | `default.nix` |

Bei Widerspruch gewinnt die speziellere Datei — und der Widerspruch gehört
aufgelöst, nicht umschifft.
