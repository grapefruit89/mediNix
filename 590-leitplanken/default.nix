# ---
# id: "leitplanken"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Leitplanken (_9) — feste UID/GID nach dem Dezimalrahmen durchsetzen (ADR-8000)"
# provides: [uid-wiring]
# tags: [leitplanken, uid, gid, isomorphie, impermanence]
# docs:
#   - docs/adr/8000-dezimalrahmen.md
#   - docs/adr/5043-dezimalrahmen.md
# ---
#
# Setzt die festen UIDs/GID, die die Registry ableitet, scharf. Ohne das laufen
# die Dienste auf automatisch vergebenen Zahlen (unter /var/lib/nixos), die bei
# Impermanence mit tmpfs-Wurzel beim Neustart verschwinden — dann bekämen die
# Dienste neue UIDs und die Mediendateien gehörten niemandem.
#
#   GID = Projekt × 1000 = 5000   (media-Gruppe, für alle geteilt)
#   UID = Projekt × 1000 + Rest   (5031 prowlarr, 5032 sonarr, …)
#
# mkForce ist nötig, weil nixpkgs manchen *arr eine statische ids.uids-Zahl gibt
# (Sonarr 274, Radarr 275, Lidarr 306) — die muss überschrieben werden.
#
# jellyseerr/seerr ist ausgenommen: läuft als systemd-DynamicUser (UID im
# Bereich 61184–65519) und greift nicht auf /data/media zu — eine feste UID
# brächte dort keinen Gewinn und erforderte das Abschalten von DynamicUser.
{
  config,
  lib,
  ...
}:
let
  cfg = config.grapefruitMedia;
  registry = import ../lib/registry.nix { inherit lib; };
  u = registry.uids;
in
{
  config = lib.mkIf cfg.enable {
    users.groups.media.gid = lib.mkForce registry.mediaGid;

    users.users.prowlarr.uid = lib.mkForce u.prowlarr;
    users.users.sonarr.uid = lib.mkForce u.sonarr;
    users.users.radarr.uid = lib.mkForce u.radarr;
    users.users.lidarr.uid = lib.mkForce u.lidarr;
    users.users.readarr.uid = lib.mkForce u.readarr;
    users.users.sabnzbd.uid = lib.mkForce u.sabnzbd;
    users.users.jellyfin.uid = lib.mkForce u.jellyfin;
    users.users.audiobookshelf.uid = lib.mkForce u.audiobookshelf;
    users.users.navidrome.uid = lib.mkForce u.navidrome;
  };
}
