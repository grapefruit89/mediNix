# ---
# id: "arr-on-demand"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Lidarr/Readarr on-demand via systemd-Socket-Aktivierung (mkArrOnDemand-Fabrik)"
# provides: [lidarr-on-demand, readarr-on-demand]
# requires: [grapefruitMedia.onDemand, lib/on-demand-http.nix]
# tags: [arr, on-demand, systemd-socket]
# docs:
#   - 50-core/adr/5033-systemd-socket-on-demand.md
#   - 50-core/archiv/claude-review.md
# ---
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
  inherit (cfg) ports;

  # H4-Fix: gemeinsame Fabrik statt duplizierter Bloecke (alt: readarr-Block war
  # Kopie des lidarr-Blocks mit anderen Werten -- H4.2 in 50-core/archiv/claude-review.md).
  mkArrOnDemand =
    {
      name,
      publicPort,
      metadataDir,
      extraEnv ? { },
    }:
    lib.mkMerge [
      (onDemand.mkProxy { inherit name publicPort; })
      (onDemand.mkIdleStop { inherit name publicPort; })
      {
        services.${name}.settings.server.port = lib.mkForce (onDemand.internalPort publicPort);

        systemd.services."${name}-backend" = {
          description = "${name} (on-demand backend)";
          after = [ "network.target" ];
          wantedBy = lib.mkForce [ ];
          environment = {
            "${lib.strings.toUpper name}__AUTH__METHOD" = if cfg.authProxyPresent then "External" else "Forms";
            "${lib.strings.toUpper name}__LOG__ANALYTICSENABLED" = "false";
            "${lib.strings.toUpper name}__LOG__LEVEL" = "info";
            "${lib.strings.toUpper name}__SERVER__PORT" = toString (onDemand.internalPort publicPort);
            "${lib.strings.toUpper name}__UPDATE__AUTOMATICALLY" = "false";
            "${lib.strings.toUpper name}__UPDATE__MECHANISM" = "external";
          }
          // extraEnv;
          serviceConfig = lib.mkMerge [
            (memory.arr { })
            {
              ExecStart = "${lib.getExe config.services.${name}.package} -nobrowser -data='/var/lib/${name}'";
              User = name;
              Group = name;
              UMask = "0002";
              # P2-3: -Prefix -- fehlende .env darf den Dienst nicht hart blockieren.
              EnvironmentFile = [ "-${cfg.secrets.secretsDir}/${name}.env" ];
              BindPaths = [ "${metadataDir}:/var/lib/${name}/MediaCover" ];
              ReadWritePaths = [
                "/var/lib/${name}"
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
    ];
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.onDemand.enable && cfg.lidarr.enable) (mkArrOnDemand {
      name = "lidarr";
      publicPort = ports.lidarr;
      metadataDir = "${cfg.storage.metadataDir}/lidarr";
      extraEnv = {
        "LIDARR__UPDATE__BRANCH" = "master";
      };
    }))
    (lib.mkIf (cfg.enable && cfg.onDemand.enable && cfg.readarr.enable) (mkArrOnDemand {
      name = "readarr";
      publicPort = ports.readarr;
      metadataDir = "${cfg.storage.metadataDir}/readarr";
      extraEnv = {
        "READARR__UPDATE__BRANCH" = "develop";
      };
    }))
  ];
}
