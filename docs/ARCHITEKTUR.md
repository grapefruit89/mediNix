---
titel: "Architektur — wie die Teile zusammenhängen"
stand: "2026-07-21"
zielgruppe: "Agenten"
error_pattern: "architektur|zusammenhang|welche datei|wo steht|was macht was"
---

# Architektur

Für Agenten geschrieben. Beantwortet drei Fragen: **wer entscheidet was**,
**wohin fließt eine Anfrage**, und **welche Datei hat bei welcher Frage recht**.

---

## 1. Vier Dinge, die oft verwechselt werden

| | Was es ist | Wo es liegt | Was es *nicht* kann |
|---|---|---|---|
| **q958** | Die Maschine. NixOS, ein Fujitsu, 15 GB RAM | `/etc/nixos` | — |
| **mediNix** | NixOS-Modul für den Medien-Stack | `github:grapefruit89/mediNix` | Nichts über Agenten wissen |
| **devNIX** | NixOS-Modul für Entwicklungswerkzeuge **+** Claude-Code-Plugin | `github:grapefruit89/devNIX` | Medien-Dienste bereitstellen |
| **devnix-agent** | Das Plugin darin: Skills, Hooks, MCP-Verdrahtung | `devNIX/plugins/devnix-agent` | Systempakete installieren |

Der häufigste Denkfehler: **ein NixOS-Modul und ein Claude-Plugin lösen
verschiedene Probleme.** Ein Modul kann `nixfmt` installieren, aber niemandem
beibringen, es zu benutzen. Ein Plugin kann Regeln erzwingen, aber kein Paket
in den PATH legen. Deshalb liegen beide in devNIX — sie sind zwei Hälften.

---

## 2. Wie q958 entsteht

```
/etc/nixos/flake.nix
├── inputs.nixpkgs      github:NixOS/nixpkgs/nixos-26.05
├── inputs.mediNix      github:grapefruit89/mediNix
├── inputs.devNIX       github:grapefruit89/devNIX
│
└── nixosConfigurations.q958
    ├── ./configuration.nix        Bootloader, de-latin1, sshd, jarvis, statische IP
    ├── ./unfree.nix               Einzelfreigaben: unrar, claude-code
    ├── ./media.nix                welche mediNix-Dienste an sind, /data-tmpfiles
    ├── ./hardening.nix            sysctl, ICMP, Source-Route
    ├── ./maintenance.nix          nix.gc
    ├── ./lifelines.nix            sshd gegen OOM schützen
    ├── ./claude.nix               maschinenspezifisch: sqlite, dig, nom
    ├── mediNix.nixosModules.default
    └── devNIX.nixosModules.default  + { devNix.enable = true; }
```

`agents.nix` gab es bis 2026-07-21 — devNIX hat es abgelöst.

**Wichtig für Änderungen:** `flake.nix` zeigt auf **GitHub**, nicht auf
`/home/jarvis/mediNix`. Wer lokal testet, darf vorübergehend auf
`git+file:///home/jarvis/mediNix` umstellen und **muss danach zurückstellen** —
sonst hängt das Bootsystem an einem schmutzigen Arbeitsverzeichnis.

Nach jeder Änderung an einem der Module:

```bash
sudo nix flake update mediNix devNIX --flake /etc/nixos
setsid nohup sudo nixos-rebuild switch --flake /etc/nixos#q958 > /tmp/sw.log 2>&1 &
```

---

## 3. Der Weg einer Anfrage

```
Browser                                       Ergebnis
   │  http://sonarr.local
   ▼
Avahi / mDNS ─────────────── 500-media-ingress/mdns.nix
   │  löst .local auf         Namensliste aus registry.uiServices
   │                          publish.userServices = true  ← ohne das: Stille
   ▼
Caddy :80 ────────────────── 500-media-ingress/default.nix
   │  vHost je Dienst         Einzelfehlerpunkt: fällt er, ist alles weg
   │                          MemoryMin + ManagedOOMPreference = avoid
   │
   ├── reverse_proxy ──────►  Dienst auf Port = Nummer × 10
   │                          sonarr 512 → 5120
   │
   └── file_server ────────►  statische Dienste (feishin)
                              try_files {path} /index.html  ← Pflicht bei SPA
```

Drei Stellen, an denen es lautlos bricht:

| Symptom | Ursache | Kapitel im Runbook |
|---|---|---|
| `.local` löst gar nicht auf, Dienst meldet exit 0 | `publish.userServices` fehlt | mDNS |
| Caddy 502, Dienst läuft aber | Dienst auf anderem Port als die Registry sagt | Port-Abweichung |
| Deep-Link 404, Startseite geht | `try_files` fehlt | Statische Dienste |

---

## 4. Wer entscheidet was

```
lib/registry.nix          ← die eine Tabelle
   │
   ├─ Port  = Nummer × 10 ──────► Dienstmodule, Caddy-vHosts
   ├─ UID   = 1000 + Nummer ────► (berechnet, NOCH NICHT verdrahtet)
   ├─ tier  ────────────────────► Ingress: edge-wan / backend-lan / none
   ├─ ui    ────────────────────► mDNS-Namen + vHost-Menge
   └─ static ───────────────────► file_server statt reverse_proxy
```

**Ein neuer Dienst = eine Zeile in der Registry plus sein Ordner.** Wer daneben
einen Port, einen Tier oder einen mDNS-Namen von Hand pflegt, hat die Registry
umgangen und einen stillen Widerspruch eingebaut.

Was **nicht** abgeleitet wird und warum: Unit-Name, State-Pfad und DNS-Name
bleiben sprechend (`sonarr.service`, `/var/lib/sonarr`). Eine Zahl ersetzt eine
Zahl — das ist Gewinn. Eine Zahl ersetzt einen Namen — das ist Verlust.
Ausführlich in `docs/adr/5042-pfadisomorphie.md`.

> **Ehrliche Lücke:** `registry.uids` und `registry.mediaGid` werden berechnet
> und **nirgends benutzt** (0 Referenzen). Real ist Sonarr UID 274 und die
> media-GID 990, automatisch vergeben. Die Isomorphie ist bei Ports umgesetzt,
> bei UIDs nicht. Wer hier arbeitet: nicht so tun, als sei das erledigt.

---

## 5. Härtung — wer darf was festlegen

`lib/service-factory.nix` ist ein Chamäleon:

```nix
harden = if enforce then lib.mkForce else lib.mkDefault;
```

`mkDefault` ist der Normalfall, damit ein fremder Betreiber übersteuern kann.
mediNix soll portabel sein — es sichert **seinen eigenen Ordner** ab, nicht den
Server des Nutzers.

Dieselbe Logik in devNIX, dort mit einer wichtigen Feinheit:

| Fall | Priorität | Warum |
|---|---|---|
| Härtung in mediNix | `mkDefault` (1000) | Betreiber gewinnt |
| `allowUnfreePredicate` in devNIX | `mkDefault` (1000) | fast jeder Host setzt es selbst |
| Shell-Aliase in devNIX | **`mkOverride 900`** | nixpkgs setzt `ll` selbst per `mkDefault` — zwei `mkDefault` **kollidieren** |

Der letzte Fall hat am 2026-07-21 einen Switch zum Scheitern gebracht. Merksatz:

> Bei gleicher Priorität gibt es einen **Konflikt**, kein „letzter gewinnt".
> Das Modulsystem ist reihenfolgeunabhängig — empirisch geprüft.

---

## 6. Die Agenten-Seite

```
Claude Code auf q958
   │
   ├── CLAUDE.md (Repo-Wurzel)      lädt immer, überlebt Compaction
   │     └── @AGENTS.md             die Verfassung
   ├── .claude/rules/*.md           lädt nach paths-Frontmatter
   ├── <ordner>/CLAUDE.md           lädt beim Anfassen des Ordners
   │
   └── Plugin devnix-agent
         ├── skills/    lage · nix-recherche · aendern · ratsche · bilanz
         ├── agents/    verifizierer
         ├── .mcp.json  nixos · context7 · github
         ├── bin/       devnix-bilanz  → im PATH
         └── hooks/     ⬅ die einzige harte Ebene
```

**Der Unterschied, den Agenten am häufigsten übersehen:** Skills und CLAUDE.md
sind *Kontext* — sie formen Verhalten, erzwingen es nicht. Nur **Hooks** laufen
unabhängig davon, wozu das Modell sich entscheidet.

| Hook | greift bei | Wirkung |
|---|---|---|
| `grenzen-bash.sh` | `PreToolUse` / Bash | Branch anlegen, Nix-Grok schreiben, `rm` auf `/data/media` und `/etc/nixos`, `systemd-run`+`nixos-rebuild` → **exit 2** |
| `grenzen-schreiben.sh` | `PreToolUse` / Write, Edit | Schreiben unter Nix-Grok → **exit 2** |
| `nixfmt-danach.sh` | `PostToolUse` / Write, Edit | `.nix` wird sofort formatiert |
| `protokoll.sh` | `PostToolUse` / alle | Strichliste je Kategorie |

`exit 1` blockt **nicht** — die Aktion läuft trotzdem, obwohl 1 der übliche
Unix-Fehlercode ist. Ein Hook mit `exit 1` sieht aus wie eine Sperre und ist
keine.

---

## 7. Welche Datei hat bei welcher Frage recht

| Frage | Datei |
|---|---|
| Port, UID, Tier, mDNS-Menge | `lib/registry.nix` |
| Warum wurde das so entschieden | `docs/adr/` |
| Was ging schief und warum | `LEARNINGS.md` |
| Etwas ist kaputt | `docs/RUNBOOK.md` |
| Regeln für alle Agenten | `AGENTS.md` |
| Regeln für Claude Code hier | `CLAUDE.md` + `.claude/rules/` |
| Regeln zu **einem** Modul | `CLAUDE.md` im jeweiligen Ordner |
| Zugänge, Ports, Fallen dieser Maschine | `CLAUDE.local.md` (gitignored) |
| Wo stehen wir gerade | `STATUS.md` |
| Historische Begründungen (K2, K4, H4.2 …) | `docs/archiv/` — **kein** Zielzustand mehr |

Bei Widerspruch gewinnt die speziellere Datei. Ein Widerspruch gehört
**aufgelöst**, nicht umschifft — und `docs/archiv/` verliert immer.

---

## 8. Was bewusst nicht hier steht

- **Wie man einen Dienst hinzufügt** → `CLAUDE.md` im jeweiligen `5xx`-Ordner
- **Wie man baut und aktiviert** → `.claude/rules/betrieb.md`
- **Wie man ein Paket prüft** → `.claude/rules/nix-recherche.md`
- **Zugangsdaten, IPs, Schlüssel** → `CLAUDE.local.md`, nie im Repo

Verlinken statt kopieren: eine zweite Kopie derselben Aussage ist eine Kopie,
die irgendwann von der ersten abweicht — und niemand merkt, welche stimmt.
