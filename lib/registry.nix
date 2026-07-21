# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Die eine Wahrheit — aus der Ordnernummer folgen Port und UID, aus dem Eintrag folgen Tier, mDNS und Ingress
#   docs:
#     - docs/adr/5042-pfadisomorphie.md
#   tags: [registry, ports, uid, isomorphie, ssot]
# ---
#
# WOZU
#
# Vorher musste man für EINEN neuen Dienst sieben Stellen anfassen:
#   default.nix Import · default.nix enable · default.nix Port ·
#   service-tiers.nix · mdns.nix Namensliste · ingress Dienst-Map · der Ordner
#
# Fünf davon waren dieselbe Information, fünfmal geschrieben. Jede Abweichung
# zwischen ihnen war ein stiller Fehler: ein Dienst mit Port, aber ohne
# mDNS-Eintrag ist erreichbar und trotzdem unauffindbar.
#
# Diese Datei ersetzt diese fünf. Übrig bleiben zwei Handgriffe:
#   1. Eine Zeile hier.
#   2. Der Modulordner.
#
# ══════════════════════════════════════════════════════════════════════════
# DIE ABLEITUNGSREGELN — und wo sie bewusst enden
# ══════════════════════════════════════════════════════════════════════════
#
# Abgeleitet wird nur, was sonst eine WILLKÜRLICHE Zahl wäre:
#
#   Port = Nummer × 10        5120 statt 8989 — niemand merkt sich 8989
#   UID  = 1000 + Nummer      1512 statt einer vergebenen Zufallszahl
#
# NICHT abgeleitet wird, was bereits einen sprechenden Namen hat:
#
#   Unit-Name    bleibt  sonarr.service       nicht media-512.service
#   State-Pfad   bleibt  /var/lib/sonarr      nicht /var/lib/media-512
#   DNS-Name     bleibt  sonarr.local         nicht sonarr.media.local
#
# Begründung: Das nixpkgs-Modul verdrahtet `systemd.services.sonarr` fest
# (servarr/sonarr.nix:73) und `StateDirectory = "sonarr"` (:125). Um daraus
# media-512 zu machen, müsste man das Modul entweder nicht benutzen und die
# Unit selbst pflegen, oder eine Alias-Unit danebenlegen — beides dauerhafter
# Aufwand gegen den Strom.
#
# Und inhaltlich: eine Zahl ersetzt eine Zahl (Gewinn), aber eine Zahl ersetzt
# keinen Namen (Verlust). Als Sonarr heute nicht startete, lautete die
# entscheidende Zeile
#     "AppFolder /var/lib/sonarr is not writable"
# Mit Nummernschema hätte dort /var/lib/media-512 gestanden — und man hätte
# erst nachschlagen müssen, welcher Dienst 512 ist.
#
# ══════════════════════════════════════════════════════════════════════════
# NUMMERNSCHEMA
# ══════════════════════════════════════════════════════════════════════════
#
#   X0 ist immer die Block-ID, nie ein Dienst.  X1–X9 sind Dienste.
#
# Die Blockreihenfolge folgt dem Weg einer Anfrage durch den Stack:
#
#   500  ingress       Eingang (Reverse-Proxy)
#   510  acquisition   Suche und Beschaffung (die *arr)
#   520  download      der eigentliche Transfer
#   530  management    Qualitäts- und Profilpflege
#   540  playback      Wiedergabe (Video, Audio, Hörbuch)
#   550  access        Benutzeranfragen
#   560  observability Metriken
#   590  security      Absicherung, quer zu allem — deshalb am Ende
#
# Keine reservierten Lücken: eine Lücke sieht aus wie ein Versehen. Neue
# Dienste bekommen die nächste freie Nummer ihres Blocks.
{ lib }:
let
  # ══════════════════════════════════════════════════════════════════════
  # DIE EINE TABELLE
  # ══════════════════════════════════════════════════════════════════════
  #
  #   number  Basis für Port und UID
  #   tier    edge-wan   = darf über die Domain nach außen
  #           backend-lan = nur im LAN
  #           none        = kein Ingress, keine Weboberfläche
  #   ui      hat eine Weboberfläche -> bekommt vHost und {name}.local
  #
  # Ein neuer Dienst = eine Zeile hier + sein Ordner. Sonst nichts.
  services = {

    # ── 500 ingress ────────────────────────────────────────────────────
    caddy = {
      number = 501;
      tier = "none";
      ui = false;
    };

    # ── 510 acquisition ────────────────────────────────────────────────
    prowlarr = {
      number = 511;
      tier = "backend-lan";
      ui = true;
    };
    sonarr = {
      number = 512;
      tier = "backend-lan";
      ui = true;
    };
    radarr = {
      number = 513;
      tier = "backend-lan";
      ui = true;
    };
    lidarr = {
      number = 514;
      tier = "backend-lan";
      ui = true;
    };
    readarr = {
      number = 515;
      tier = "backend-lan";
      ui = true;
    };

    # ── 520 download ───────────────────────────────────────────────────
    sabnzbd = {
      number = 521;
      tier = "backend-lan";
      ui = true;
    };

    # ── 530 management ─────────────────────────────────────────────────
    # Kein ui: Recyclarr ist ein Timer ohne Oberfläche.
    recyclarr = {
      number = 531;
      tier = "none";
      ui = false;
    };

    # ── 540 playback ───────────────────────────────────────────────────
    jellyfin = {
      number = 541;
      tier = "edge-wan";
      ui = true;
    };
    audiobookshelf = {
      number = 542;
      tier = "edge-wan";
      ui = true;
    };
    navidrome = {
      number = 543;
      tier = "edge-wan";
      ui = true;
    };

    # ── 550 access ─────────────────────────────────────────────────────
    jellyseerr = {
      number = 551;
      tier = "edge-wan";
      ui = true;
    };

    # ── 560 observability ──────────────────────────────────────────────
    # Metriken-Endpunkt, keine Oberfläche für Menschen.
    exportarr = {
      number = 561;
      tier = "none";
      ui = false;
    };

    # ── 590 security ───────────────────────────────────────────────────
    # Kein Dienst mit Port, sondern ein Confinement-Mechanismus. Die Nummer
    # existiert der Vollständigkeit halber; Port und UID werden nicht genutzt.
    usenet-confinement = {
      number = 591;
      tier = "none";
      ui = false;
    };
  };

  # ══════════════════════════════════════════════════════════════════════
  # ABLEITUNG
  # ══════════════════════════════════════════════════════════════════════
  portOf = svc: svc.number * 10;
  uidOf = svc: 1000 + svc.number;

  withUi = lib.filterAttrs (_: s: s.ui) services;
  inTier = tier: lib.attrNames (lib.filterAttrs (_: s: s.tier == tier) services);
in
{
  inherit services;

  # Port und UID je Dienst — ersetzt die 14 handgepflegten Port-Optionen
  ports = lib.mapAttrs (_: portOf) services;
  uids = lib.mapAttrs (_: uidOf) services;

  # Tier-Zuordnung — ersetzt lib/service-tiers.nix
  byService = lib.mapAttrs (_: s: s.tier) services;
  edgeServices = inTier "edge-wan";
  backendServices = inTier "backend-lan";
  noneServices = inTier "none";
  tierOf = name: services.${name}.tier or "none";

  # Dienste mit Oberfläche — ersetzt die Namensliste in mdns.nix
  # und die Dienst-Map im Ingress
  uiServices = lib.attrNames withUi;

  # ══════════════════════════════════════════════════════════════════════
  # FIXE MEDIA-GRUPPE — die eine bewusste Ausnahme von der Isomorphie
  # ══════════════════════════════════════════════════════════════════════
  #
  # Die GID wird NICHT aus der Nummer abgeleitet. Täte sie es, bekäme jeder
  # Dienst seine eigene Gruppe — Sonarr schriebe mit GID 1512, Jellyfin wollte
  # mit 1541 lesen, Ergebnis: Permission denied. Das ist der klassische
  # Docker-PUID/PGID-Fehler in Nix-Form.
  #
  # Der gesamte Sinn des Musters ist eine GEMEINSAME Gruppe für alle Dienste
  # am selben Bibliothekspfad.
  #
  # Warum fix und nicht automatisch vergeben: NixOS legt automatische Zuordnungen
  # unter /var/lib/nixos ab. Bei Impermanence mit tmpfs-Wurzel verschwindet das
  # beim Neustart, wenn es nicht persistiert wird — die Gruppe bekäme eine neue
  # GID, und bestehende Dateien gehörten plötzlich niemandem.
  # Auf q958 gemessen (2026-07-20): GID war 990, automatisch vergeben.
  #
  # 3000 gewählt, weil:
  #   < 1000  ist bei NixOS für Systemkonten reserviert (misc/ids.nix)
  #   = 1000  ist auf den meisten Systemen der erste echte Benutzer
  mediaGid = 3000;
}
