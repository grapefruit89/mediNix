---
titel: "Onboarding — von der leeren Maschine bis alles läuft"
stand: "2026-07-21"
zielgruppe: "Agenten"
error_pattern: "onboarding|neue maschine|von vorne|wie fange ich an|setup|einrichten"
---

# Onboarding

Von einer frisch installierten NixOS-Maschine bis zu elf laufenden Diensten und
einem einsatzfähigen Agenten.

**Reihenfolge einhalten.** Jeder Schritt endet mit einer Prüfung. Schlägt sie
fehl, ist der nächste Schritt sinnlos — dann zum Runbook, nicht weitermachen.

---

## Bevor du anfängst

| Voraussetzung | Prüfen mit |
|---|---|
| NixOS ist installiert und bootet | `nixos-version` |
| Ein Benutzer mit `wheel` und passwortlosem `sudo` | `sudo -n true && echo ok` |
| SSH-Zugang mit Schlüssel | `ssh <user>@<host>` |
| Flakes sind eingeschaltet | `nix flake --help >/dev/null 2>&1 && echo ok` |

Fehlt das Letzte:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

> **Diese Anleitung baut kein NixOS.** Sie setzt eine bootende Maschine voraus.
> Die Installation selbst ist ein anderes Thema — Fallen dabei stehen in
> `CLAUDE.local.md`.

---

## Schritt 1 — Netzwerk, das nicht wegläuft

Auf q958 gibt der Router **kein DHCPv4**. `dhcpcd` wartet zehn Sekunden und
fällt auf `169.254.x.x` zurück. Deshalb steht die Adresse statisch:

```nix
networking.hostName = "q958";
networking.interfaces.eno1.ipv4.addresses = [{
  address = "192.168.2.73";
  prefixLength = 24;
}];
networking.defaultGateway = "192.168.2.1";
networking.nameservers = [ "192.168.2.1" ];
console.keyMap = "de-latin1";
```

**Prüfen**

```bash
ip -4 addr show eno1 | grep inet
ping -c1 -W2 192.168.2.1 && echo "Gateway ok"
curl -sI https://github.com -o /dev/null -w '%{http_code}\n'
```

> **Typisches Symptom bei kaputtem IPv4:** `cache.nixos.org` ist erreichbar
> (hat IPv6), GitHub nicht (hat keins). Wer „manche Hosts gehen, andere nicht"
> sieht, prüft **zuerst IPv4/IPv6** — nicht den Dienst.

---

## Schritt 2 — mDNS, sonst ist später nichts erreichbar

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
  publish = {
    enable = true;
    addresses = true;
    userServices = true;   # ← ohne das: KEIN einziger Name, ohne Fehlermeldung
  };
};
```

**Prüfen — von einem *anderen* Rechner:**

```bash
ping -c1 q958.local
```

`publish.addresses` und `publish.userServices` sind **nicht** dasselbe. Fehlt
das zweite, veröffentlicht Avahi nichts und meldet trotzdem `exit 0`.
Runbook, Abschnitt 5.

---

## Schritt 3 — Die Flake verdrahten

`/etc/nixos/flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    mediNix = {
      url = "github:grapefruit89/mediNix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devNIX = {
      url = "github:grapefruit89/devNIX";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, mediNix, devNIX }: {
    nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        ./hardware-configuration.nix
        ./unfree.nix
        ./media.nix
        mediNix.nixosModules.default
        devNIX.nixosModules.default
        { devNix.enable = true; }
      ];
    };
  };
}
```

> **Immer auf GitHub zeigen lassen, nie auf ein Arbeitsverzeichnis.** Zum Testen
> darf `mediNix.url` vorübergehend auf `git+file:///home/<user>/mediNix` stehen —
> **danach zwingend zurückstellen**, sonst hängt das Bootsystem an einer
> schmutzigen Arbeitskopie.

`unfree.nix` — Einzelfreigaben statt globalem `allowUnfree`:

```nix
{ lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "unrar" "claude-code" ];
}
```

`unrar` zieht SABnzbd über seine Abhängigkeiten, `claude-code` ist proprietär.
**Setzt du hier ein eigenes Prädikat, muss `claude-code` darin stehen** — es
gewinnt gegen devNIX' `mkDefault`. Eine Assertion in devNIX weist darauf hin.

---

## Schritt 4 — Welche Dienste, und wohin die Daten

`/etc/nixos/media.nix`:

```nix
{ ... }:
{
  grapefruitMedia = {
    enable = true;
    domain = null;              # null = nur .local, kein WAN
    jellyfin.enable = true;
    audiobookshelf.enable = true;
    navidrome.enable = true;
    feishin = {
      enable = true;
      serverUrl = "http://navidrome.local";
      serverType = "navidrome";
    };
    sonarr.enable = true;
    radarr.enable = true;
    readarr.enable = true;
    lidarr.enable = true;
    prowlarr.enable = true;
    sabnzbd.enable = true;
    jellyseerr.enable = true;
  };

  systemd.tmpfiles.rules = [
    "d /data                   0775 root media - -"
    "d /data/media             0775 root media - -"
    "d /data/media/tv          0775 root media - -"
    "d /data/media/movies      0775 root media - -"
    "d /data/media/music       0775 root media - -"
    "d /data/media/books       0775 root media - -"
    "d /data/media/audiobooks  0775 root media - -"
    "d /data/downloads         0775 root media - -"
  ];
}
```

**Ports musst du nicht angeben.** Sie folgen aus `lib/registry.nix`:
Ordnernummer × 10. Sonarr liegt in `530-beschaffung` mit Nummer 512, also 5120.
Wer hier einen Port hart setzt, umgeht die Registry.

**Was du bewusst weglässt:**

| Option | warum aus |
|---|---|
| `exporters.enable` | Erzeugt derzeit weder Units noch Ports — ungeklärt |
| `recyclarr.enable` | `trash_ids` ungeprüft, falsche IDs zerlegen still die Profile |
| `usenetConfinement` | braucht einen WireGuard-Schlüssel |
| `provision` | braucht API-Schlüssel |

---

## Schritt 5 — Bauen und aktivieren

```bash
sudo nixos-rebuild dry-build --flake /etc/nixos#<host>

setsid nohup sudo nixos-rebuild switch --flake /etc/nixos#<host> \
  > /tmp/sw.log 2>&1 &
```

**`setsid nohup`, niemals `systemd-run`.** Letzteres gibt der Unit einen
minimalen PATH; `nixos-rebuild` scheitert darin mit `[Errno 2] … 'test'` — und
der Switch gilt trotzdem als erfolgreich. Runbook, Abschnitt 10.

**Prüfen — der Ausgabe nicht glauben:**

```bash
tail -3 /tmp/sw.log
[ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ] \
  && echo BOOTFEST || echo "nicht bootfest -- switch nachholen"
```

`nixos-rebuild test` überlebt keinen Neustart. Wer mit `test` aufhört, verliert
alles.

---

## Schritt 6 — Nachweisen, dass es wirklich läuft

**Von einem anderen Rechner**, nicht von der Maschine selbst:

```bash
for s in jellyfin sonarr radarr readarr lidarr prowlarr sabnzbd \
         navidrome jellyseerr audiobookshelf feishin; do
  printf "%-16s %s\n" "$s" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$s.local)"
done
```

**Erwartete Antworten** — Abweichung ist der Befund:

| Antwort | Dienste | Bedeutung |
|---|---|---|
| `302` | jellyfin, die fünf *arr, navidrome | Weiterleitung auf Login |
| `303` | sabnzbd | eigene Weiterleitung |
| `307` | jellyseerr | temporäre Weiterleitung |
| `200` | audiobookshelf, feishin | liefern ihre SPA direkt |
| `502` | — | **Fehler.** Runbook, Abschnitt 6 |

`curl 127.0.0.1:<port>` beweist **nicht**, dass es läuft — es umgeht mDNS und
Caddy, also genau die zwei Schichten, die am häufigsten brechen.

Ein Dienst gilt erst als gesund, wenn **alle drei** stimmen:

```bash
systemctl is-active <dienst>
systemctl show <dienst> -p NRestarts --value    # muss 0 sein
sudo ss -tlnp | grep <dienst>                   # Port = Nummer × 10
```

Jellyfin war einmal `active` mit 0 Neustarts — und lauschte auf dem falschen
Port. Caddy lieferte 502. Ein laufender Dienst kann unerreichbar sein.

---

## Schritt 7 — Den Agenten einsatzfähig machen

```bash
claude plugin marketplace add grapefruit89/devNIX
claude plugin install devnix-agent@devnix
```

Läuft bereits eine Sitzung: `/reload-plugins`. Sonst reicht der nächste Start.

**Prüfen**

```bash
claude plugin list                  # devnix-agent  enabled
command -v nixfmt nixf-diagnose statix deadnix shellcheck jq
devnix-bilanz --kurz
```

Fehlt `jq`, laufen **alle Hooks still ins Leere** und keine Sperre greift, ohne
dass es auffällt. `devNix.enable = true` bringt es mit.

**Was danach anders ist**

| | |
|---|---|
| Skills | `/devnix-agent:lage` · `:nix-recherche` · `:aendern` · `:ratsche` · `:bilanz` |
| Subagent | `verifizierer` — prüft Behauptungen ohne Vorgeschichte |
| Gesperrt | Branch anlegen · Schreiben in Nix-Grok · `rm` auf `/data/media` und `/etc/nixos` · `systemd-run`+`nixos-rebuild` |
| Automatisch | `.nix` wird nach jedem Schreiben formatiert, jeder Werkzeugaufruf protokolliert |

---

## Die drei häufigsten Aufgaben

### Einen neuen Dienst hinzufügen

**Zwei Handgriffe, nicht sieben.**

1. Eine Zeile in `lib/registry.nix`:

```nix
    navidrome = {
      number = 543;      # → Port 5430, UID 1543
      tier = "edge-wan"; # edge-wan | backend-lan | none
      ui = true;         # bekommt vHost und navidrome.local
    };
```

2. Der Ordner `543-navidrome/` mit `default.nix`. Er wird **automatisch**
   eingebunden — dreistellige Nummer genügt, keine Import-Zeile.

Nicht anfassen: mDNS-Namensliste, Ingress-Dienstkarte, Tier-Tabelle. Alles
abgeleitet. Details in `CLAUDE.md` des jeweiligen `5xx`-Ordners.

### Einen Port ändern

Gar nicht direkt. Die Nummer in der Registry ändern — Port, UID und Tier folgen.
Steht ein Port irgendwo hart im Code, ist das ein Fehler, kein Feature.

### Eine Änderung an mediNix ausprobieren

```bash
cd ~/mediNix
git add -A && git commit -m "..."          # 1. VOR den Werkzeugen
nixcheck                                    # 2. nixfmt · nixf-diagnose · statix · deadnix · shellcheck
git add -A && git commit -m "lint"          # 3. danach
git show HEAD                               # 4. Diff prüfen — der Zweck der Trennung
# 5. push nur nach Zustimmung im Chat

sudo nix flake update mediNix --flake /etc/nixos
setsid nohup sudo nixos-rebuild switch --flake /etc/nixos#<host> > /tmp/sw.log 2>&1 &
```

Die Commit-Trennung hat sich sofort bewährt: `deadnix --edit` machte aus
`{ lib }:` ein `{ }:` und zerlegte alle Aufrufer. In einem gemeinsamen Commit
wäre das untergegangen.

---

## Wen fragen — hier: welche Datei

| Frage | Antwort steht in |
|---|---|
| Wie hängt das alles zusammen | `docs/ARCHITEKTUR.md` |
| Etwas ist kaputt | `docs/RUNBOOK.md` — Fehlerzeile gegen `error_pattern` matchen |
| Warum ist das so entschieden | `docs/adr/` |
| Was ging schon mal schief | `LEARNINGS.md` |
| Wo stehen wir gerade | `STATUS.md` |
| Port, UID, Tier, mDNS | `lib/registry.nix` |
| Regeln für alle Agenten | `AGENTS.md` |
| Regeln für diesen Ordner | `CLAUDE.md` im Ordner |
| Zugänge, IPs, Fallen der Maschine | `CLAUDE.local.md` — gitignored |
| Historische Begründungen (K2, K4) | `docs/archiv/` — **kein** Zielzustand |

Bei Widerspruch gewinnt die speziellere Datei, und `docs/archiv/` verliert
immer. Ein Widerspruch gehört aufgelöst, nicht umschifft.

---

## Was du beim Aufräumen liegen lässt

Sieht überflüssig aus, ist es nicht:

| | |
|---|---|
| `lib/service-tiers.nix` | Weiterleitung auf die Registry, von `ddns.nix` importiert. Eine Textsuche nach `registry.byService` findet nichts — der Zugriff läuft über die Weiterleitung |
| `compat-my.nix` | Bewusst nicht importiert. Bildet `my.*` auf `grapefruitMedia.*` ab, falls jemand mediNix in Nix-Grok einbindet |
| `registry.uids`, `mediaGid` | Verdrahtet (wireFixedUids), auf q958 aktiv |
| `docs/archiv/` | 18 Code-Kommentare verweisen auf Befunde darin |

> **Erst Gegentest, dann aufräumen.** Entferne den Verdächtigen und vergleiche
> den Store-Pfad. Bleibt er bitgleich, war es wirklich tot — sagt eine
> Textsuche nichts, kann sie trotzdem falsch liegen.

---

## Wenn ein Schritt fehlschlägt

1. **Nicht weitermachen.** Ein fehlgeschlagener Schritt macht alle folgenden
   sinnlos.
2. Fehlerzeile wörtlich nehmen und im `docs/RUNBOOK.md` gegen die
   `error_pattern` matchen.
3. Steht sie dort nicht: erst die GitHub-Issues des betroffenen Pakets, bevor
   debuggt wird.
4. Ursache **beweisen**, nicht vermuten — Bedingung wegnehmen, prüfen ob es
   bricht. Der teuerste Fehler dieses Projekts war eine plausible, ungeprüfte
   Vermutung.
5. Neuen Fall ins Runbook eintragen, **mit** der widerlegten Erstannahme. Ohne
   sie dokumentiert der Eintrag nur die Lösung, nicht den Denkfehler.
