> ## Hinweis — dies ist KEIN ADR
>
> Dieses Dokument ist die **Quelle**, aus der ADR-5042 entstanden ist: ein
> Brainstorm-Ergebnis, kritisch überarbeitet. Es hat bewusst kein
> ADR-Frontmatter und ist nicht über `error_pattern` auffindbar.
>
> **Die Entscheidung steht in [`5042-pfadisomorphie.md`](5042-pfadisomorphie.md).**
> Dieses Dokument erklärt nur, woher sie kommt — und was davon beim
> Übernehmen begründet abgelehnt wurde.
>
> Es liegt in `adr/`, weil es zu ADR-5042 gehört. Wer nach einer Entscheidung
> sucht, liest das andere.

---

# Nix-Grok · Modul `50-media` — Pfadisomorphie-Konzept

**Stand:** Ergebnis einer Konzeptions-Session (Chat-Brainstorm mit DeepSeek als Ideengeber, hier kritisch geprüft, korrigiert und finalisiert).
**Status:** Nummerierung und Grundarchitektur sind entschieden. Zwei offene technische Punkte vor dem produktiven Rollout (siehe Abschnitt 6).

---

## 1. Grundidee

Eine einzige Zahl — die **Ordnernummer** — ist die Basis (Source of Truth), aus der alles andere, was im System eine Nummer braucht, deterministisch abgeleitet wird: Port, UID, Socket-Pfad, State-Verzeichnis, systemd-Unit-Name, DNS-Name.

Ziel: Keine manuellen Portlisten mehr, keine verstreuten Pfade, keine Karteileichen — eine Registry-Datei ist die einzige Wahrheit.

### Ableitungsregeln

| Was | Regel | Beispiel (Jellyfin, Nummer 541) |
|---|---|---|
| Ordnernummer | Basis | 541 |
| Port | Nummer × 10 | 5410 |
| UID | 1000 + Nummer | 1541 |
| GID | **fix, NICHT isomorph** (siehe Abschnitt 4) | `mediaGid` (Konstante) |
| Socket | `/run/media-${Nummer}.sock` | `/run/media-541.sock` |
| State-Pfad | `/var/lib/media-${Nummer}/` | `/var/lib/media-541/` |
| Unit-Name | `media-${Nummer}.service` | `media-541.service` |
| DNS-Name | `${serviceName}.media.local` | `jellyfin.media.local` |

**Bewusst verworfen:** API-Key-Prefix nach Schema (z. B. Key beginnt mit `5410`). Reduziert Entropie im Secret messbar, ohne echten Mehrwert — der Dateiname (`/var/lib/credentials/jellyfin_api_key`) identifiziert den Dienst bereits eindeutig. Wurde in einer früheren Iteration vorgeschlagen, dann explizit wieder verworfen.

---

## 2. Nummerierungsschema — die verbindliche Struktur

### 2.1 Die eine Regel, ausnahmslos

> **`X0` ist immer Block-ID (nie ein Dienst). `X1`–`X9` sind konkrete Dienste.**

Gilt für jeden Zehnerblock, unabhängig davon, ob ein oder fünf Dienste darin liegen. Keine Ausnahmen, keine Sonderfälle für Single-Service-Blöcke.

### 2.2 Keine reservierten Lücken

Kategorien, für die aktuell kein Dienst vorgesehen ist, tauchen **nicht** als Platzhalter in der Nummerierung auf (kein "frei für später"). Alle belegten Blöcke rücken lückenlos aneinander, damit keine Lücke wie ein Versehen wirkt. Einzige bewusste Ausnahme: der Sprung zu **590 (Security)** am Ende — das ist keine "vergessene Lücke", sondern der bewusste, von Anfang an stabile Abschluss-Block für Sicherheit, losgelöst von der linearen Pipeline-Reihenfolge.

### 2.3 Pipeline-Logik der Blockreihenfolge

Ein Media-Request durchläuft: **Ingress → Suche/Beschaffung (Arrs) → Download → Verwaltung → Wiedergabe → Benutzerzugriff**, mit Sicherheit als Querschnittsthema ganz am Ende.

| Block | Kategorie (englisch) | Bedeutung |
|---|---|---|
| 500–509 | `ingress` | Netzwerk-Eingang (Reverse-Proxy) |
| 510–519 | `acquisition` | Such-/Indexer- und Beschaffungs-Orchestratoren (die Arrs) |
| 520–529 | `download` | Download-Clients (führen den eigentlichen Transfer aus) |
| 530–539 | `management` | Qualitäts-/Profil-Sync, Verwaltung |
| 540–549 | `playback` | Alle Wiedergabe-Dienste (Video, Audio, Hörbücher) zusammen |
| 550–559 | `access` | Benutzerzugriff / Requests |
| 590–599 | `security` | Absicherung, Kill-Switches, Assertions |

**Wichtige Korrektur gegenüber dem ursprünglichen DeepSeek-Brainstorm:** Player (Jellyfin) stand dort fälschlich am Anfang (510), noch vor den Arrs und dem Download — das widerspricht dem tatsächlichen Datenfluss. Ebenso waren Wiedergabe-Dienste (Jellyfin/Audiobookshelf/Navidrome) über drei verschiedene Zehnerblöcke verstreut, was das Grundprinzip "ein Zehnerblock = eine Funktion" gebrochen hätte. Beides wurde korrigiert.

### 2.4 Finale, verbindliche Tabelle

| Nummer | Service | Port | UID | GID | Kategorie | Ordner |
|---|---|---|---|---|---|---|
| 501 | Caddy | 5010 | 1501 | `mediaGid` | ingress | `500-ingress/` |
| 511 | Prowlarr | 5110 | 1511 | `mediaGid` | acquisition | `510-arrs/` |
| 512 | Sonarr | 5120 | 1512 | `mediaGid` | acquisition | `510-arrs/` |
| 513 | Radarr | 5130 | 1513 | `mediaGid` | acquisition | `510-arrs/` |
| 514 | Lidarr | 5140 | 1514 | `mediaGid` | acquisition | `510-arrs/` |
| 515 | Readarr | 5150 | 1515 | `mediaGid` | acquisition | `510-arrs/` |
| 521 | Sabnzbd | 5210 | 1521 | `mediaGid` | download | `520-download/` |
| 522 | Transmission | 5220 | 1522 | `mediaGid` | download | `520-download/` |
| 531 | Recyclarr | 5310 | 1531 | `mediaGid` | management | `530-management/` |
| 541 | Jellyfin | 5410 | 1541 | `mediaGid` | playback | `540-playback/` |
| 542 | Audiobookshelf | 5420 | 1542 | `mediaGid` | playback | `540-playback/` |
| 543 | Navidrome | 5430 | 1543 | `mediaGid` | playback | `540-playback/` |
| 551 | Jellyseerr | 5510 | 1551 | `mediaGid` | access | `550-access/` |
| 591 | VPN-Confinement | 5910 | 1591 | `mediaGid` | security | `590-security/` |

### 2.5 Ordnerstruktur (Flake-Modul)

```
modules/50-media/
├── flake-module.nix           # (oder default.nix, je nach Konvention)
├── lib/
│   └── registry.nix           # zentrale Ableitungslogik, siehe Abschnitt 3
├── 500-ingress/
│   └── 501-caddy.nix
├── 510-arrs/
│   ├── 511-prowlarr.nix
│   ├── 512-sonarr.nix
│   ├── 513-radarr.nix
│   ├── 514-lidarr.nix
│   └── 515-readarr.nix
├── 520-download/
│   ├── 521-sabnzbd.nix
│   └── 522-transmission.nix
├── 530-management/
│   └── 531-recyclarr.nix
├── 540-playback/
│   ├── 541-jellyfin.nix
│   ├── 542-audiobookshelf.nix
│   └── 543-navidrome.nix
├── 550-access/
│   └── 551-jellyseerr.nix
└── 590-security/
    └── 591-vpn-confinement.nix
```

**Namensraum-Hinweis:** Als NixOS-Options-Namespace wurde in früheren Entwürfen `grapefruitMedia` verwendet — das war ein Platzhaltername aus dem Brainstorm und sollte vor dem produktiven Einbau konsistent zu deiner sonstigen Nix-Grok-Namenskonvention benannt werden (z. B. `my.media.*` oder was auch immer dein SSoT-Schema sonst nutzt), damit es nicht mit `mediNix`/Nix-Grok in der restlichen Doku kollidiert.

---

## 3. Die Registry — zentrale Ableitungslogik

```nix
# modules/50-media/lib/registry.nix
{ config, lib, ... }:
let
  # ─── FIXE MEDIA-GRUPPE ──────────────────────────────────────────────────
  # Bewusste Ausnahme von der Pfadisomorphie: alle Dienste, die auf
  # denselben Library-Pfad zugreifen, teilen sich EINE Gruppe.
  # Bezieht sich aus der zentralen SSoT, nicht literal hier verdrahtet.
  mediaGid = config.my.uids.mediaGroup;

  # ─── SERVICE-DEFINITIONEN ────────────────────────────────────────────────
  # Regel: X0 ist immer Block-ID (nie ein Dienst). X1-X9 sind Dienste.
  services = {
    # ─── 500: INGRESS ─────────────────────────────────────────────────────
    caddy = { number = 501; category = "ingress"; serviceName = "caddy"; };

    # ─── 510: ARRS (Suche & Beschaffung) ──────────────────────────────────
    prowlarr = { number = 511; category = "acquisition"; serviceName = "prowlarr"; };
    sonarr   = { number = 512; category = "acquisition"; serviceName = "sonarr"; };
    radarr   = { number = 513; category = "acquisition"; serviceName = "radarr"; };
    lidarr   = { number = 514; category = "acquisition"; serviceName = "lidarr"; };
    readarr  = { number = 515; category = "acquisition"; serviceName = "readarr"; };

    # ─── 520: DOWNLOAD ─────────────────────────────────────────────────────
    sabnzbd      = { number = 521; category = "download"; serviceName = "sabnzbd"; };
    transmission = { number = 522; category = "download"; serviceName = "transmission"; };

    # ─── 530: MANAGEMENT ───────────────────────────────────────────────────
    recyclarr = { number = 531; category = "management"; serviceName = "recyclarr"; };

    # ─── 540: PLAYBACK ─────────────────────────────────────────────────────
    jellyfin       = { number = 541; category = "playback"; serviceName = "jellyfin"; };
    audiobookshelf = { number = 542; category = "playback"; serviceName = "audiobookshelf"; };
    navidrome      = { number = 543; category = "playback"; serviceName = "navidrome"; };

    # ─── 550: ACCESS ───────────────────────────────────────────────────────
    jellyseerr = { number = 551; category = "access"; serviceName = "jellyseerr"; };

    # ─── 590: SECURITY ─────────────────────────────────────────────────────
    vpn-confinement = { number = 591; category = "security"; serviceName = "vpn-confinement"; };
  };

  # ─── ABLEITUNGSFUNKTIONEN ────────────────────────────────────────────────
  derivePort     = service: service.number * 10;
  deriveUid      = service: 1000 + service.number;
  deriveGid      = service: mediaGid;                                   # FIX, nicht isomorph
  deriveSocket   = service: "/run/media-${toString service.number}.sock";
  deriveStateDir = service: "/var/lib/media-${toString service.number}";
  deriveUnitName = service: "media-${toString service.number}.service";
  deriveDnsName  = service: "${service.serviceName}.media.local";

  # ─── NUR AKTIVE DIENSTE ──────────────────────────────────────────────────
  activeServices = lib.filterAttrs
    (name: _: config.grapefruitMedia.${name}.enable or false)   # Namespace ggf. anpassen, s.o.
    services;

  mkMap = fn: lib.mapAttrs' (name: service: {
    name = name;
    value = fn service;
  }) activeServices;

in {
  # ─── EXPORT ───────────────────────────────────────────────────────────────
  services = services;      # alle (auch inaktive) – für Doku/Assertions
  active   = activeServices;

  ports     = mkMap derivePort;
  uids      = mkMap deriveUid;
  gids      = mkMap deriveGid;
  sockets   = mkMap deriveSocket;
  stateDirs = mkMap deriveStateDir;
  unitNames = mkMap deriveUnitName;
  dnsNames  = mkMap deriveDnsName;

  # ─── HELPER: EINZELNE DIENSTE NACH NAME ─────────────────────────────────
  get         = name: activeServices.${name} or null;
  portOf      = name: derivePort (get name);
  uidOf       = name: deriveUid (get name);
  gidOf       = name: deriveGid (get name);
  socketOf    = name: deriveSocket (get name);
  stateDirOf  = name: deriveStateDir (get name);
  unitNameOf  = name: deriveUnitName (get name);
  dnsNameOf   = name: deriveDnsName (get name);
}
```

### Beispiel-Verwendung in einem Service-Modul

```nix
# modules/50-media/510-arrs/512-sonarr.nix
{ config, lib, pkgs, ... }:
let
  registry = import ../lib/registry.nix { inherit config lib; };
  port     = registry.portOf "sonarr";
  uid      = registry.uidOf "sonarr";
  stateDir = registry.stateDirOf "sonarr";
in {
  config = lib.mkIf config.grapefruitMedia.sonarr.enable {
    services.sonarr = {
      settings.server.port = port;
      dataDir = stateDir;
    };
  };
}
```

---

## 4. Kritischer Fehler (aus früherer Iteration) — GID ≠ UID

### Das Problem

Eine frühere Version hatte `deriveGid = service: 1000 + service.number;` — also **isomorph wie die UID**. Das ist der klassische Docker-PUID/PGID-Fehler in Nix-Form: Jeder Dienst bekäme seine eigene, isolierte Gruppe (Sonarr = GID 1512, Jellyfin = GID 1541 usw.). Sonarr schreibt eine Datei mit GID 1512, Jellyfin will sie mit GID 1541 lesen → **Permission denied**.

Der gesamte Sinn des Arr-Stack-Musters ist eine **gemeinsame** Gruppe, der alle Download-/Playback-Dienste angehören, damit sie sich gegenseitig Dateien lesen/schreiben können.

### Die Lösung — bewusste Ausnahme von der Pfadisomorphie

> **UID ist isomorph (`1000 + Nummer`). GID ist bewusst NICHT isomorph — sie ist eine fixe Konstante für alle Dienste, die denselben Library-Pfad teilen.**

Diese Ausnahme ist kein Stilbruch, sondern funktionale Notwendigkeit und sollte im Code auch so kommentiert werden ("einzige bewusste Durchbrechung der Pfadisomorphie, aus funktionaler Notwendigkeit").

### Welche GID nehmen? (Best Practice)

- **UIDs/GIDs < 1000** sind bei NixOS für System-Accounts reserviert (`nixos/modules/misc/ids.nix`) — meiden, auch wenn dort Lücken frei erscheinen, weil künftige NixOS-Versionen dort neue System-User einführen können.
- **GID/UID 1000** ist bei den meisten Linux-Installationen der **erste normale Benutzer-Account** (vermutlich dein eigener) — Kollisionsrisiko, unbedingt meiden.
- Empfehlung: eine GID klar außerhalb beider Bereiche wählen, z. B. **3000**, und diese **fix in der zentralen `my.uids`-SSoT** hinterlegen (nicht literal in der Registry verdrahtet):

```nix
# my-ssot/uids.nix (oder wo deine zentrale SSoT liegt)
{
  my.uids.mediaGroup = 3000;
}
```

```nix
# einmalig, global
users.groups.media.gid = config.my.uids.mediaGroup;
```

Die konkrete Zahl ist letztlich zweitrangig — entscheidend ist, dass sie **fix in der SSoT steht** und **durch eine Build-Time-Assertion vor Kollisionen mit anderen Domain-Layern (00–90) geschützt wird.**

### Wichtiger Zusatzpunkt wegen Impermanence/tmpfs-root

Falls die GID **nicht** fix vergeben, sondern NixOS automatisch zuweisen lassen wird: NixOS speichert diese automatische Zuordnung typischerweise unter `/var/lib/nixos/*`. Bei einem Impermanence-Setup mit tmpfs-root kann dieser Pfad beim Reboot verschwinden, wenn er nicht explizit persistiert wird — dann bekäme die Gruppe bei jedem Neustart potenziell eine andere GID, und bestehende Dateien würden plötzlich "niemandem" mehr gehören. Das ist ein zusätzlicher, konkreter Grund, warum die feste GID hier nicht nur sauberer, sondern **notwendig** ist.

---

## 5. `mkHardened` / `DynamicUser` — KISS-Lösung

### Das Problem

Hardening-Factories wie `mkHardened` setzen häufig standardmäßig `DynamicUser = true` — systemd erfindet dann bei jedem Service-Start eine zufällige, temporäre UID/GID, unabhängig davon, was in der Registry als GID vorgesehen ist. Falls das bei `mkHardened` der Fall ist, würde die gesamte GID-Festlegung aus Abschnitt 4 wirkungslos verpuffen.

**Ob das bei Nix-Grok tatsächlich zutrifft, wurde in dieser Session nicht verifiziert** (Live-Zugriff auf den Server war aus der Chat-Umgebung heraus nicht möglich). Prüfbefehl für den Server:

```bash
grep -rn "DynamicUser" /etc/nixos/Nix-Grok/ --include="*.nix" | grep -i hardened
```

### Die KISS-Lösung — funktioniert in beiden Fällen, ganz ohne die Prüfung abzuwarten

`SupplementaryGroups` wirkt unabhängig davon, ob `DynamicUser` an oder aus ist. Das macht die Prüfung optional (nur zur nachträglichen Bestätigung nötig, nicht als Voraussetzung):

```nix
# einmalig, global — eine feste Gruppe für alles Media-bezogene
users.groups.media.gid = config.my.uids.mediaGroup;
```

```nix
# in der mkHardened-Factory: eine Zeile ergänzen, unabhängig vom DynamicUser-Zustand
serviceConfig.SupplementaryGroups = [ "media" ];
```

Minimalste Lösung mit den wenigsten beweglichen Teilen: eine globale Gruppendefinition + eine Zeile im Hardening-Wrapper. Kein Umbau des gesamten Hardening-Patterns nötig, `DynamicUser` kann unverändert bestehen bleiben (Sicherheitsvorteil bleibt erhalten).

**Entscheidung aus der Session:** Diese eine Zeile soll **pauschal bei allen Media-Diensten** gelten (kein optionaler Schalter pro Dienst nötig) — einfacher, konsistenter, und passt zum expliziten Wunsch nach KISS mit minimalen Moving Parts.

---

## 6. Offene Punkte vor dem produktiven Rollout

| # | Punkt | Status |
|---|---|---|
| 1 | `config.my.uids.mediaGroup` in der zentralen SSoT anlegen (empfohlen: `3000`, oder andere Zahl außerhalb System-Range `<1000` und Erst-User-Range `1000`) | **offen** |
| 2 | Verifizieren, ob `mkHardened` tatsächlich `DynamicUser = true` setzt (Grep-Befehl siehe Abschnitt 5) | **offen — Live-Check auf dem Server nötig** |
| 3 | `SupplementaryGroups = [ "media" ]` pauschal in `mkHardened` einbauen | **offen — Umsetzung ausstehend** |
| 4 | Options-Namespace (`grapefruitMedia` war Platzhalter) konsistent zur sonstigen Nix-Grok-Konvention benennen | **offen** |
| 5 | Registry (`my.ports.*`, `my.uids.*`, `my.gids.*`) in die zentrale SSoT einspeisen statt isoliert zu betreiben, damit Build-Time-Assertions Kollisionen mit anderen Domain-Layern (00–90) erkennen können | **offen — Architekturentscheidung nötig, wie genau gemerged wird** |
| 6 | Tmpfiles-Regeln für Library-Pfade (`root:media`, korrekte Schreibrechte) | **noch nicht ausgearbeitet** |
| 7 | Caddy-vHost-Generierung automatisch aus der Registry (`dnsNames`) | **noch nicht ausgearbeitet** |

---

## 7. Bewusst NICHT im Media-Stack (bestätigte Entscheidungen)

Diese Dienste/Themen wurden im Verlauf der Session explizit diskutiert und **verworfen**, um Scope-Creep zu vermeiden:

| Verworfen | Warum |
|---|---|
| PostgreSQL, Valkey/Redis | Kein Media-Dienst — die Arrs nutzen SQLite, das reicht |
| Prometheus, Grafana, Uptime Kuma, Scrutiny, Netdata | Observability/Monitoring ist Overkill für den reinen Media-Stack |
| n8n, Ollama | Automatisierung/KI — kein Media-Dienst |
| Exportarr | Reiner Prometheus-Exporter für die Arr-APIs — Monitoring, kein Media-Dienst |
| Fail2ban, Firewall, SSH, Cert-Management | Host-Infrastruktur, nicht Teil des Media-Stack-Flakes |
| Pocket-ID / SSO | Host-Infrastruktur (SSO); falls gewünscht, nur als optionaler Enable-Switch im Media-Modul, Pocket-ID selbst läuft auf dem Host |
| Logging (zentral), Homepage/Dashboard | In früheren Iterationen diskutiert, dann aber ebenfalls als "Host-Sache" bzw. optional eingestuft — **in der finalen Tabelle (Abschnitt 2.4) nicht mehr enthalten** |
| **Maintainerr** (automatisches Bibliotheks-Cleanup) | Kein natives NixOS-Paket vorhanden — wird ausschließlich als Docker-Image (`ghcr.io/maintainerr/maintainerr`) vertrieben. Keine `services.maintainerr`-Option in nixpkgs. Drei Optionen wurden benannt: (a) `virtualisation.oci-containers` — bricht die sonst reine systemd/`mkHardened`-Linie; (b) selbst als `buildNpmPackage`-Derivation paketieren — nicht trivial (NestJS+Next.js-Monorepo); (c) stattdessen eigenes Cleanup-Script direkt gegen die Sonarr/Radarr-APIs bauen, als systemd-Timer. **Entscheidung: erstmal komplett weggelassen.** Alternative Tools, die genannt wurden, aber nicht geprüft: Janitorr (ebenfalls nur Docker-Image) |

---

## 8. Zusammenfassung für den schnellen Wiedereinstieg

1. Nummerierung 500–591 ist final (Tabelle 2.4).
2. `registry.nix` ist fertig entworfen (Abschnitt 3), aber referenziert `config.my.uids.mediaGroup`, die noch nicht existiert (Punkt 6.1).
3. GID ist bewusst fix, nicht isomorph — funktionale Notwendigkeit, kein Kompromiss (Abschnitt 4).
4. `DynamicUser`-Kollision mit fixer GID ist ungeklärt, aber die Lösung (`SupplementaryGroups`) funktioniert so oder so — muss nur noch eingebaut werden (Abschnitt 5).
5. Maintainerr ist raus, kein Ersatz aktuell final entschieden.
6. Vor dem ersten Deploy: SSoT-Integration der Registry (Punkt 6.5) und Namespace-Umbenennung (Punkt 6.4) sind die wichtigsten strukturellen ToDos, damit sich das nicht wiederholt, was in früheren Runden schiefging (parallele Wahrheitsquellen, kaputte Assertions).
