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
      number = 511;
      tier = "none";
      ui = false;
    };

    # ── 510 acquisition ────────────────────────────────────────────────
    prowlarr = {
      number = 531;
      tier = "backend-lan";
      ui = true;
    };
    sonarr = {
      number = 532;
      tier = "backend-lan";
      ui = true;
    };
    radarr = {
      number = 533;
      tier = "backend-lan";
      ui = true;
    };
    lidarr = {
      number = 534;
      tier = "backend-lan";
      ui = true;
    };
    readarr = {
      number = 535;
      tier = "backend-lan";
      ui = true;
    };

    # ── 520 download ───────────────────────────────────────────────────
    sabnzbd = {
      number = 541;
      tier = "backend-lan";
      ui = true;
    };

    # ── 530 management ─────────────────────────────────────────────────
    # Kein ui: Recyclarr ist ein Timer ohne Oberfläche.
    recyclarr = {
      number = 571;
      tier = "none";
      ui = false;
    };

    # ── 540 playback ───────────────────────────────────────────────────
    jellyfin = {
      number = 551;
      tier = "edge-wan";
      ui = true;
    };
    audiobookshelf = {
      number = 552;
      tier = "edge-wan";
      ui = true;
    };
    navidrome = {
      number = 553;
      tier = "edge-wan";
      ui = true;
    };
    # Feishin: alternative Oberflaeche fuer Navidrome/Jellyfin/OpenSubsonic.
    #
    # BESONDERHEIT static = true: feishin-web sind reine statische Dateien
    # (index.html + assets), kein Server. Caddy liefert sie direkt aus --
    # kein eigener Prozess, keine Unit, kein belegter Port.
    #
    # Die Nummer 544 vergeben wir trotzdem: sie ordnet den Dienst dem
    # Playback-Block zu und haelt die Tabelle vollstaendig. Der daraus
    # abgeleitete Port 5440 wird nicht benutzt.
    #
    # Feishin ERSETZT Navidrome nicht -- es spricht dessen API. Ohne einen
    # laufenden Musikserver zeigt es nur eine Anmeldemaske.
    feishin = {
      number = 554;
      tier = "edge-wan";
      ui = true;
      static = true;
    };

    # ── 550 access ─────────────────────────────────────────────────────
    jellyseerr = {
      number = 561;
      tier = "edge-wan";
      ui = true;
    };

    # ── 560 observability ──────────────────────────────────────────────
    # Ein Exporter je *arr-Dienst. Jeder bekommt eine eigene Nummer statt
    # eines Sammeleintrags -- sonst braeuchte man wieder eine Nebenrechnung
    # ("Basisport plus Versatz"), und genau die wollte das Schema abschaffen.
    # Keine Oberfläche für Menschen, deshalb ui = false und tier = none.
    exportarr-sonarr = {
      number = 573;
      tier = "none";
      ui = false;
    };
    exportarr-radarr = {
      number = 574;
      tier = "none";
      ui = false;
    };
    exportarr-prowlarr = {
      number = 575;
      tier = "none";
      ui = false;
    };
    exportarr-lidarr = {
      number = 576;
      tier = "none";
      ui = false;
    };

    # ── 590 security ───────────────────────────────────────────────────
    # Kein Dienst mit Port, sondern ein Confinement-Mechanismus. Die Nummer
    # existiert der Vollständigkeit halber; Port und UID werden nicht genutzt.
    usenet-confinement = {
      number = 521;
      tier = "none";
      ui = false;
    };
  };

  # ══════════════════════════════════════════════════════════════════════
  # ABLEITUNG
  # ══════════════════════════════════════════════════════════════════════
  # static: Dienste ohne eigenen Prozess. Caddy liefert ihre Dateien direkt
  # aus (file_server statt reverse_proxy). Default false -- die allermeisten
  # Dienste lauschen auf einem Port.
  isStatic = svc: svc.static or false;

  portOf = svc: svc.number * 10;
  # UID = Projekt × 1000 + Rest (ADR-8000). Projekt = fuehrende Ziffer,
  # Rest = die zwei Ziffern danach. 532 -> 5*1000 + 32 = 5032. Fuehrt mit der
  # Projektziffer wie Port und GID; kann nie X000 sein (N00 ist nie ein Dienst).
  uidOf =
    svc:
    let
      projekt = svc.number / 100;
    in
    projekt * 1000 + (svc.number - projekt * 100);

  withUi = lib.filterAttrs (_: s: s.ui) services;
  inTier = tier: lib.attrNames (lib.filterAttrs (_: s: s.tier == tier) services);
in
{
  inherit services;

  # Port je Dienst — ersetzt die 14 handgepflegten Port-Optionen.
  # Wird benutzt: default.nix leitet daraus die Port-Defaults ab.
  ports = lib.mapAttrs (_: portOf) services;

  # ══════════════════════════════════════════════════════════════════════
  # uids — BERECHNET, ABER BEWUSST NOCH NICHT VERDRAHTET
  # ══════════════════════════════════════════════════════════════════════
  #
  # Gegengeprüft am 2026-07-21: dieses Feld hat NULL Leser. Entfernt man es,
  # bleibt der Store-Pfad der Prüfkonfiguration bitgleich — es ist wirkungslos.
  #
  # Es steht trotzdem hier, weil es eine ENTSCHEIDUNG trägt, keine Vergesslichkeit:
  # ADR-5042 legt fest, dass UIDs isomorph aus der Nummer folgen sollen.
  # Löschte man das Feld, verschwände die Entscheidung mitsamt Begründung — das
  # Problem bliebe, nur unsichtbar.
  #
  #   Soll (dieses Feld)      Ist (auf q958 gemessen)
  #   sonarr   1512           sonarr   274
  #   radarr   1513           radarr   275
  #   jellyfin 1541           jellyfin 993
  #
  # WAS DIE VERDRAHTUNG KOSTET — und warum sie nicht nebenbei passiert:
  # Die *arr-Module aus nixpkgs legen ihre Benutzer selbst an. Eine feste UID
  # erzwingt `users.users.<dienst>.uid = registry.uids.<dienst>` PLUS einen
  # einmaligen `chown -R` über /var/lib/<dienst>, sonst gehören die vorhandenen
  # Dateien nach dem Switch niemandem mehr. Ohne diesen Schritt startet kein
  # einziger Dienst mehr.
  #
  # WARUM ES TROTZDEM DRINGEND IST: automatisch vergebene UIDs liegen unter
  # /var/lib/nixos. Bei Impermanence mit tmpfs-Wurzel ist das nach dem Neustart
  # weg — die Dienste bekommen neue UIDs, und die Mediendateien gehören
  # plötzlich niemandem. Genau der Fall, vor dem ADR-5042 warnt.
  #
  # Status: offen. Siehe STATUS.md, Punkt 2 der nächsten Sitzung.
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

  # Dienste, die Caddy als statische Dateien ausliefert statt sie zu proxen
  staticServices = lib.attrNames (lib.filterAttrs (_: isStatic) services);
  isStaticService = name: (services.${name} or { }).static or false;

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
  # 5000 gewählt (geändert von 3000 am 2026-07-21). Zwei Bedingungen, ein Wunsch:
  #
  #   SICHER  NixOS vergibt System-Gruppen 400–999 abwärts (erreicht 5000 nie)
  #           und reguläre User 1000–29999 aufwärts (5000 erst nach 4000 Usern).
  #           5000 liegt in KEINEM automatisch vergebenen Pfad. Geprüft.
  #   FREI    von den abgeleiteten UIDs (1501–1591) weit entfernt.
  #   ERKENNBAR  Sieht man in einer Rechte-Fehlermeldung `gid 5000`, ist sofort
  #           klar: das gehört zu mediNix. Genau der Sinn des 5xx-Namensraums.
  #
  # Warum NICHT die naheliegenden Alternativen:
  #   500   liegt IM System-Bereich 400–999. Heute frei, aber der Automat zählt
  #         abwärts und erreicht es irgendwann -> Zeitbombe. Verboten.
  #   3000  war der alte Wert. Sicher, aber ohne Erkennungswert — „3000, wo
  #         gehört das hin?". 5000 beantwortet die Frage von selbst.
  #
  # Es gibt keinen Port 5000: Ports sind Nummer×10, und 500 ist die Ingress-
  # Block-ID (X0 ist nie ein Dienst). Also keine Verwechslung mit dem Portraum.
  #
  # ⚠ BERECHNET, ABER NOCH NICHT VERDRAHTET (Stand 2026-07-21). Real ist die
  # GID auf q958 990, automatisch vergeben. Entfernt man dieses Feld, bleibt der
  # Store-Pfad bitgleich. Zum Verdrahten: `users.groups.media.gid = registry.mediaGid;`
  # plus einmaliger `chgrp -R` über /data/media — zusammen mit der UID-Migration.
  mediaGid = 5000;
}
