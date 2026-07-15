{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  factory = import ../lib/service-factory.nix { inherit lib; };
  memory = import ../lib/memory-policy.nix {
    inherit lib;
    ramGB = cfg.hardware.ramGB;
  };

  arrApps = {
    sonarr = {
      port = cfg.ports.sonarr;
      metadataDir = "${cfg.storage.metadataDir}/sonarr";
      extraEnv = {
        SONARR__UPDATE__BRANCH = "main";
      };
    };
    radarr = {
      port = cfg.ports.radarr;
      metadataDir = "${cfg.storage.metadataDir}/radarr";
      extraEnv = {
        RADARR__UPDATE__BRANCH = "master";
      };
    };
    readarr = {
      port = cfg.ports.readarr;
      metadataDir = "${cfg.storage.metadataDir}/readarr";
      extraEnv = {
        READARR__UPDATE__BRANCH = "develop";
      };
    };
    prowlarr = {
      port = cfg.ports.prowlarr;
      metadataDir = "${cfg.storage.metadataDir}/prowlarr";
      extraEnv = {
        PROWLARR__UPDATE__BRANCH = "master";
      }
      // lib.optionalAttrs cfg.usenet-confinement.enable {
        PROWLARR__UPDATE__MECHANISM = lib.mkForce "External";
      };
    };
    lidarr = {
      port = cfg.ports.lidarr;
      metadataDir = "${cfg.storage.metadataDir}/lidarr";
      extraEnv = {
        LIDARR__UPDATE__BRANCH = "master";
      };
    };
  };

  mkArrService =
    {
      name,
      port,
      dataDir,
      metadataDir ? null,
      upstreamHost ? "127.0.0.1",
      extraEnv ? { },
      onDemand ? false,
    }:
    let
      nameUpper = lib.strings.toUpper name;
    in
    lib.mkMerge [
      {
        users.groups.${name} = {};
        users.users.${name} = {
          group = name;
          isSystemUser = true;
          extraGroups = [ "media" ];
        };
      }

      (lib.mkIf (!onDemand) {
        services.${name} = {
          enable = true;
          openFirewall = false;
          inherit dataDir;
          settings.server.port = port;
        };

        systemd.services.${name}.environment = {
          "${nameUpper}__AUTH__METHOD" = lib.mkForce "External";
          "${nameUpper}__LOG__LEVEL" = lib.mkDefault "info";
        }
        // extraEnv;

        systemd.tmpfiles.rules = lib.mkIf (metadataDir != null) [
          "d ${metadataDir} 0775 ${name} media -"
          "d /var/lib/${name}/MediaCover 0755 ${name} ${name} -"
        ];
      })

      (lib.mkIf (!onDemand) (
        factory.mkService {
          inherit config name port upstreamHost;
          mode = "sso";
          hardeningProfile = "dotnet";
          persistDirs = [ dataDir ];
          readWritePaths = [
            dataDir
            "${cfg.storage.mediaRoot}/downloads"
            "${cfg.storage.mediaRoot}/media"
          ];
          readOnlyPaths = [ ];
          memoryPolicy = memory.arr { };
          extraSystemd = {
            UMask = lib.mkForce "0002";
            EnvironmentFile = [ "${cfg.secrets.secretsDir}/${name}.env" ];
            BindPaths = lib.mkIf (metadataDir != null) [
              "${metadataDir}:/var/lib/${name}/MediaCover"
            ];
          };
        }
      ))
    ];

  mkArr =
    name: app:
    let
      dataDir = "/var/lib/${name}";
      useOnDemand = cfg.onDemand.enable && (name == "lidarr" || name == "readarr");
    in
    lib.mkIf (cfg.enable && cfg.${name}.enable) (
      mkArrService (
        {
          inherit name dataDir;
          onDemand = useOnDemand;
        }
        // app
      )
    );
in
{
  config = lib.mkMerge (lib.mapAttrsToList mkArr arrApps);
}
