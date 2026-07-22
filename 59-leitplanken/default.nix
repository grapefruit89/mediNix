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
# Setzt die festen UIDs/GID, die die Registry ableitet:
#   GID = Projekt × 1000 = 5000   (media-Gruppe, geteilt)
#   UID = Nummer × 10   (5310 prowlarr … 5530 navidrome)
#
# OPT-IN über `grapefruitMedia.wireFixedUids`. Aus per Default, weil feste UIDs
# eine einmalige `chown`-Migration der State-Verzeichnisse brauchen — sonst
# starten Dienste mit „permission denied". Ein Host schaltet es bewusst ein,
# wenn er migriert hat oder ein frisches System ohne Daten hat. Die
# Prüfkonfiguration lässt es aus und bleibt so berührungsfrei.
#
# Jede UID zusätzlich an den jeweiligen Dienst gekoppelt (mkIf …enable): so
# entstehen nie Teil-Benutzer ohne isSystemUser/Gruppe, wenn ein Dienst aus ist.
#
# mkForce, weil nixpkgs manchen *arr eine statische ids.uids-Zahl gibt
# (Sonarr 274, Radarr 275, Lidarr 306). jellyseerr/seerr ist ausgenommen:
# DynamicUser (61184–65519), greift nicht auf /data/media zu.
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
  options.grapefruitMedia.wireFixedUids = lib.mkEnableOption ''
    feste UIDs/GID nach dem Dezimalrahmen (ADR-8000) durchsetzen. Braucht eine
    einmalige chown-Migration der State-Verzeichnisse — deshalb Opt-in
  '';

  config = lib.mkIf (cfg.enable && cfg.wireFixedUids) (
    lib.mkMerge [
      { users.groups.media.gid = lib.mkForce registry.mediaGid; }
      (lib.mkIf cfg.prowlarr.enable { users.users.prowlarr.uid = lib.mkForce u.prowlarr; })
      (lib.mkIf cfg.sonarr.enable { users.users.sonarr.uid = lib.mkForce u.sonarr; })
      (lib.mkIf cfg.radarr.enable { users.users.radarr.uid = lib.mkForce u.radarr; })
      (lib.mkIf cfg.lidarr.enable { users.users.lidarr.uid = lib.mkForce u.lidarr; })
      (lib.mkIf cfg.readarr.enable { users.users.readarr.uid = lib.mkForce u.readarr; })
      (lib.mkIf cfg.sabnzbd.enable { users.users.sabnzbd.uid = lib.mkForce u.sabnzbd; })
      (lib.mkIf cfg.jellyfin.enable { users.users.jellyfin.uid = lib.mkForce u.jellyfin; })
      (lib.mkIf cfg.audiobookshelf.enable {
        users.users.audiobookshelf.uid = lib.mkForce u.audiobookshelf;
      })
      (lib.mkIf cfg.navidrome.enable { users.users.navidrome.uid = lib.mkForce u.navidrome; })
    ]
  );
}
