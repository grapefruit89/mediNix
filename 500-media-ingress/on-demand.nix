{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  onDemand = import ../lib/on-demand-http.nix {
    inherit lib pkgs;
    internalOffset = cfg.onDemand.internalOffset;
    idleTimeoutSec = cfg.onDemand.idleTimeoutSec;
  };
  memory = import ../lib/memory-policy.nix {
    inherit lib;
    ramGB = cfg.hardware.ramGB;
  };
  ports = cfg.ports;
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.onDemand.enable && cfg.lidarr.enable) (
      lib.mkMerge [
        (onDemand.mkProxy { name = "lidarr"; publicPort = ports.lidarr; })
        (onDemand.mkIdleStop { name = "lidarr"; publicPort = ports.lidarr; })
        {
          services.lidarr.settings.server.port = lib.mkForce (onDemand.internalPort ports.lidarr);

          systemd.services.lidarr-backend = {
            description = "lidarr (on-demand backend)";
            after = [ "network.target" ];
            wantedBy = lib.mkForce [ ];
            environment = {
              "LIDARR__AUTH__METHOD" = "External";
              "LIDARR__LOG__ANALYTICSENABLED" = "false";
              "LIDARR__LOG__LEVEL" = "info";
              "LIDARR__SERVER__PORT" = toString (onDemand.internalPort ports.lidarr);
              "LIDARR__UPDATE__AUTOMATICALLY" = "false";
              "LIDARR__UPDATE__MECHANISM" = "external";
              "LIDARR__UPDATE__BRANCH" = "master";
            };
            serviceConfig = lib.mkMerge [
              (memory.arr { })
              {
                ExecStart = "${lib.getExe config.services.lidarr.package} -nobrowser -data='/var/lib/lidarr'";
                User = "lidarr";
                Group = "lidarr";
                UMask = "0002";
                EnvironmentFile = [ "${cfg.secrets.secretsDir}/lidarr.env" ];
                BindPaths = [ "${cfg.storage.metadataDir}/lidarr:/var/lib/lidarr/MediaCover" ];
                ReadWritePaths = [
                  "/var/lib/lidarr"
                  "${cfg.storage.mediaRoot}/downloads"
                  "${cfg.storage.mediaRoot}/media"
                ];
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
                LockPersonality = true;
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                SystemCallFilter = [
                  "@system-service"
                  "~@privileged"
                ];
              }
            ];
          };
        }
      ]
    ))

    (lib.mkIf (cfg.enable && cfg.onDemand.enable && cfg.readarr.enable) (
      lib.mkMerge [
        (onDemand.mkProxy { name = "readarr"; publicPort = ports.readarr; })
        (onDemand.mkIdleStop { name = "readarr"; publicPort = ports.readarr; })
        {
          services.readarr.settings.server.port = lib.mkForce (onDemand.internalPort ports.readarr);

          systemd.services.readarr-backend = {
            description = "readarr (on-demand backend)";
            after = [ "network.target" ];
            wantedBy = lib.mkForce [ ];
            environment = {
              "READARR__AUTH__METHOD" = "External";
              "READARR__LOG__ANALYTICSENABLED" = "false";
              "READARR__LOG__LEVEL" = "info";
              "READARR__SERVER__PORT" = toString (onDemand.internalPort ports.readarr);
              "READARR__UPDATE__AUTOMATICALLY" = "false";
              "READARR__UPDATE__MECHANISM" = "external";
              "READARR__UPDATE__BRANCH" = "develop";
            };
            serviceConfig = lib.mkMerge [
              (memory.arr { })
              {
                ExecStart = "${lib.getExe config.services.readarr.package} -nobrowser -data='/var/lib/readarr'";
                User = "readarr";
                Group = "readarr";
                UMask = "0002";
                EnvironmentFile = [ "${cfg.secrets.secretsDir}/readarr.env" ];
                BindPaths = [ "${cfg.storage.metadataDir}/readarr:/var/lib/readarr/MediaCover" ];
                ReadWritePaths = [
                  "/var/lib/readarr"
                  "${cfg.storage.mediaRoot}/downloads"
                  "${cfg.storage.mediaRoot}/media"
                ];
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
                LockPersonality = true;
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                SystemCallFilter = [
                  "@system-service"
                  "~@privileged"
                ];
              }
            ];
          };
        }
      ]
    ))
  ];
}
