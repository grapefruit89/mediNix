# Prüfkonfiguration: der VOLLE Stack, wie q958 ihn fährt.
#
# WARUM es das zusätzlich zu minimal-host.nix gibt:
# minimal-host lässt die Einzeldienste aus (enable = true nur auf grapefruitMedia).
# Der `eval`-Check baut damit ein praktisch LEERES System — er beweist nur, dass
# das Modulgerüst evaluiert, nicht dass Jellyfin, die *arr oder jellyseerr bauen.
# Das war ein blinder Fleck: ein kaputtes Dienstmodul wäre in CI grün geblieben
# und erst auf echter Hardware aufgefallen.
#
# Diese Konfiguration schaltet jeden Dienst ein (Spiegel von /etc/nixos/media.nix)
# und der `full`-Check baut daraus den kompletten system.build.toplevel — also
# jede Dienst-Ableitung. Bricht ein Modul, bricht CI, nicht erst der Switch.
{ lib, ... }:
{
  # sabnzbd zieht unrar (unfrei, kostenlos nutzbar) -- wie q958s unfree.nix.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "unrar" ];

  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/dummy";
    fsType = "ext4";
  };
  system.stateVersion = "26.05";

  grapefruitMedia = {
    enable = true;
    wireFixedUids = true;
    domain = null;

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
    exporters.enable = true;
  };
}
