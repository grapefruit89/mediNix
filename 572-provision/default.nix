# ---
# id: "media-provision"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Deklarative Erstkonfiguration der Media-Dienste ueber ihre REST-APIs (Opt-in)"
# provides: [arr-sync-* oneshot services]
# requires: [grapefruitMedia.provision, grapefruitMedia.secrets]
# tags: [provisioning, arr, api, opt-in]
# docs:
#   - modules/50-media/README.md
# ---
#
# Portiert aus Nix-Grok `56-arr-sync/` (ADR-5034 Scope-Cut wird hiermit aufgehoben,
# aber bewusst als OPT-IN statt im Kern).
#
# Was das macht: nach dem Boot sprechen oneshot-Services die REST-APIs der Dienste
# an und verdrahten den Stack, statt dass man sich durch fuenf Web-UIs klickt --
# API-Keys injizieren, TRaSH-Host-Settings, SABnzbd als Download-Client in jedem
# *arr registrieren, Prowlarr-Indexer + App-Sync, Jellyfin-Bootstrap,
# Jellyseerr-Bootstrap, Quality-Profile, Locale/Kategorien.
#
# WARUM OPT-IN (Default aus):
#   Das ist imperative Glue -- API-Calls zur Laufzeit gegen Dienste, die ihren
#   Zustand in eigenen DBs halten. Es ist maechtig, aber es ist NICHT der
#   deklarative Kern. Wer den schlanken, portablen Stack will, laesst es aus;
#   wer "konfiguriert sich selbst" will, schaltet einen Schalter um.
#
# ALLE Sub-Module haengen zusaetzlich am Master-Switch `provision.enable`.
# Ihre eigenen `.enable`-Flags stehen auf mkDefault true, damit ein einziges
# `provision.enable = true` den sinnvollen Vollausbau aktiviert.
{ lib, ... }:
{
  imports = [
    ./keys.nix
    ./settings.nix
    ./download-clients.nix
    ./prowlarr.nix
    ./profiles.nix
    ./locale.nix
    ./jellyfin.nix
    ./seerr.nix
  ];

  options.grapefruitMedia.provision = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master-Schalter fuer die deklarative Erstkonfiguration ueber die
        REST-APIs der Dienste.

        Default AUS: der Kern des Moduls bleibt rein deklarativ und schlank.
        Auf true gesetzt, verdrahtet sich der Stack nach dem Boot selbst
        (Indexer, Download-Clients, Profile, Bibliotheken, Locale).

        Einzelne Bereiche lassen sich danach gezielt abschalten, z.B.
        `provision.prowlarr.enable = false`.
      '';
    };
  };
}
