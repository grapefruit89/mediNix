# ---
# id: "jellyseerr"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Jellyseerr -- Request-Manager (aus 551-jellyfin herausgeloest, ADR-5043)"
# provides: [seerr]
# requires: [grapefruitMedia.jellyfin]
# tags: [jellyseerr, seerr, requests, media]
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  factory = import ../lib/service-factory.nix { inherit lib; };
  cfgJellyseerr = cfg.jellyseerr;
  portJellyseerr = cfg.ports.jellyseerr;
in
{
  config = lib.mkIf (cfg.enable && cfgJellyseerr.enable) (
    lib.mkMerge [
      {
        services.seerr = {
          enable = true;
          port = portJellyseerr;
          openFirewall = false;
          package = lib.mkIf (cfgJellyseerr.package != null) cfgJellyseerr.package;
        };
      }
      (factory.mkService {
        inherit config;
        name = "seerr";
        port = portJellyseerr;
        persistDirs = [ "/var/lib/seerr" ];
        readWritePaths = [ "/var/lib/seerr" ];
      })
      {
        systemd.services.seerr.serviceConfig.EnvironmentFile = lib.mkForce [
          "-${cfg.secrets.jellyseerrEnvFile}"
        ];
        systemd.services.seerr.serviceConfig.ExecStartPre =
          let
            walScript = pkgs.writeShellScript "seerr-wal-pragma" ''
              DB="/var/lib/seerr/db/db.sqlite3"
              [ -f "$DB" ] || exit 0
              ${pkgs.sqlite}/bin/sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null
              echo "seerr: SQLite WAL mode activated"
            '';
          in
          lib.mkBefore [ "+${walScript}" ];
      }
    ]
  );
}
