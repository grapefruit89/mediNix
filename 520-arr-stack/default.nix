# ---
# id: "arr-stack"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Sonarr/Radarr/Readarr/Prowlarr/Lidarr -- gemeinsame Fabrik mit Security-Baseline"
# provides: [sonarr, radarr, readarr, prowlarr, lidarr]
# requires: [grapefruitMedia.storage, grapefruitMedia.secrets]
# ports: [5003, 5004, 5005, 5006, 5010]
# state_dir: "/var/lib/{name}"
# tags: [arr, servarr, media, security]
# docs:
#   - modules/50-media/claude-review.md
#   - docs/adr/5030-media-stack-factory-hardening.md
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

      # H4-Fix: tmpfiles immer aktiv (auch bei onDemand.enable=true),
      # damit BindPaths in on-demand.nix nicht scheitert.
      (lib.mkIf (metadataDir != null) {
        systemd.tmpfiles.rules = [
          "d ${metadataDir} 0775 ${name} media -"
          # Elternverzeichnis MUSS vor MediaCover stehen. Sonst legt systemd-
          # tmpfiles es beim Anlegen des Unterordners implizit als root:root an,
          # und Dienste mit statischem User= (Sonarr, Radarr) koennen nicht
          # schreiben -> "AppFolder /var/lib/sonarr is not writable", EPIC FAIL.
          # Prowlarr entging dem nur, weil es DynamicUser + StateDirectory nutzt.
          # Auf q958 am 2026-07-20 reproduziert.
          "d /var/lib/${name} 0750 ${name} ${name} -"
          "d /var/lib/${name}/MediaCover 0755 ${name} ${name} -"
        ];
      })

      (lib.mkIf (!onDemand) {
        services.${name} = {
          enable = true;
          openFirewall = false;
          inherit dataDir;
          settings.server.port = port;
          settings.server.bindaddress = "127.0.0.1";
          # Nur setzen wenn der Konsument ein Override angegeben hat --
          # sonst bleibt der nixpkgs-Default des Moduls gueltig.
          package = lib.mkIf (cfg.${name}.package != null) cfg.${name}.package;
        };

        systemd.services.${name}.environment = {
          "${nameUpper}__AUTH__METHOD" = lib.mkForce (if cfg.authProxyPresent then "External" else "Forms");
          "${nameUpper}__LOG__LEVEL" = lib.mkDefault "info";
        }
        // extraEnv;
      })

      (lib.mkIf (!onDemand) (
        factory.mkService {
          inherit config name port;
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
            # P2-3: -Prefix -- systemd ignoriert die Datei wenn sie (noch) fehlt,
            # statt den Dienst hart zu blockieren (Parität zu Jellyseerr/Navidrome).
            EnvironmentFile = [ "-${cfg.secrets.secretsDir}/${name}.env" ];
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
  config = lib.mkMerge [
    (lib.mkMerge (lib.mapAttrsToList mkArr arrApps))
    {
      # K2-Warning: Kein Auth-Proxy -> Forms-Fallback aktiv (kein Eval-Bruch mehr)
      warnings = lib.optional (cfg.enable && !cfg.authProxyPresent) ''
        [50-media/arr-stack] Kein Forward-Auth-Proxy deklariert
        (grapefruitMedia.authProxyPresent = false) -- *arr-Apps laufen mit
        AUTH__METHOD=Forms (lokaler Login). Fuer SSO: authProxyPresent = true
        setzen, wenn oauth2-proxy/Pocket-ID vor dem Ingress steht.
      '';
    }
  ];
}
