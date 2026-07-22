# ---
# id: "provision-prowlarr"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Prowlarr-Indexer + App-Registrierungen deklarativ"
# provides: [arr-sync-prowlarr.service]
# requires: [grapefruitMedia.provision]
# tags: [provisioning, prowlarr, indexer]
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  prov = cfg.provision;
  sub = prov.prowlarr;
  inherit (cfg) ports;
  arrProvision = pkgs.callPackage ../../packages/arr-provision { };

  loopback = "127.0.0.1";

  autoApps = lib.filterAttrs (_: v: v.enabled) {
    sonarr = {
      enabled = cfg.sonarr.enable;
      port = ports.sonarr;
      apiVersion = "v3";
      apiKeyFile = cfg.secrets.sonarrApiKeyFile;
    };
    radarr = {
      enabled = cfg.radarr.enable;
      port = ports.radarr;
      apiVersion = "v3";
      apiKeyFile = cfg.secrets.radarrApiKeyFile;
    };
    readarr = {
      enabled = cfg.readarr.enable;
      port = ports.readarr;
      apiVersion = "v1";
      apiKeyFile = cfg.secrets.readarrApiKeyFile;
    };
    lidarr = {
      enabled = cfg.lidarr.enable;
      port = ports.lidarr;
      apiVersion = "v1";
      apiKeyFile = cfg.secrets.lidarrApiKeyFile;
    };
  };

  appsJson = builtins.toJSON (
    lib.mapAttrsToList (name: app: {
      inherit name;
      inherit (app) port apiVersion apiKeyFile;
      host = loopback;
    }) autoApps
  );

  active = cfg.enable && prov.enable && sub.enable && cfg.prowlarr.enable;
in
{
  options.grapefruitMedia.provision.prowlarr = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prowlarr deklarativ befuellen: Indexer anlegen + *arr als Applications registrieren.";
    };

    syncLevel = lib.mkOption {
      type = lib.types.enum [
        "addOnly"
        "fullSync"
        "disabled"
      ];
      default = "fullSync";
      description = "Prowlarr-Sync-Level fuer die Application-Registrierungen.";
    };

    indexers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Indexer-Name in Prowlarr.";
            };
            protocol = lib.mkOption {
              type = lib.types.str;
              default = "usenet";
              description = "Protokoll: usenet oder torrent.";
            };
            implementation = lib.mkOption {
              type = lib.types.str;
              default = "Newznab";
              description = "Prowlarr-Indexer-Implementation (z.B. Newznab, Torznab).";
            };
            configContract = lib.mkOption {
              type = lib.types.str;
              default = "NewznabSettings";
              description = "Prowlarr configContract (muss zur Implementation passen).";
            };
            baseUrl = lib.mkOption {
              type = lib.types.str;
              description = "Basis-URL des Indexers.";
            };
            apiKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Pfad zur Datei mit dem Indexer-API-Key (leer = kein Key noetig).";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Indexer, die deklarativ in Prowlarr registriert werden.

        Die API-Keys der Indexer kommen als Dateipfade -- niemals als Klartext
        in die Nix-Config, sonst landen sie im world-readable Nix-Store.
      '';
    };

    backupIndexers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Indexer-Name in den *arr (Suffix '(Backup)' empfohlen).";
            };
            baseUrl = lib.mkOption {
              type = lib.types.str;
              description = "Basis-URL des Indexers.";
            };
            apiKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Pfad zur Datei mit dem Indexer-API-Key.";
            };
            categories = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [
                5000
                5100
                5140
                2000
                2100
                2140
              ];
              description = "Newznab-Kategorie-IDs (TV + Movies Standard).";
            };
            targetApps = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "*arr, die diesen Indexer erhalten (leer = alle aktiven).";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Indexer, die direkt (unabhaengig vom Prowlarr-Sync) als deaktivierter
        Backup-Eintrag in den *arr angelegt werden -- als Fallback, wenn Prowlarr
        selbst ausfaellt.
      '';
    };
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-prowlarr = {
      description = "Provision: Prowlarr indexers + application registration";
      after = [
        "prowlarr.service"
      ]
      ++ lib.optional cfg.sonarr.enable "sonarr.service"
      ++ lib.optional cfg.radarr.enable "radarr.service";
      wants = [ "prowlarr.service" ];
      wantedBy = [ "multi-user.target" ];

      startLimitIntervalSec = 600;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 5;
      };

      environment = {
        PROWLARR_HOST = loopback;
        PROWLARR_PORT = toString ports.prowlarr;
        PROWLARR_KEY_FILE = cfg.secrets.prowlarrApiKeyFile;
        PROWLARR_DB = "/var/lib/prowlarr/prowlarr.db";
        # Prowlarr laeuft ggf. in der VPN-Sandbox -- das Script braucht das Wissen.
        PROWLARR_VPN_SANDBOX = if cfg.usenet-confinement.enable then "1" else "0";
        HOST_BRIDGE = loopback;
        SYNC_LEVEL = sub.syncLevel;
        INDEXERS_JSON = builtins.toJSON sub.indexers;
        APPS_JSON = appsJson;
        BACKUP_INDEXERS_JSON = builtins.toJSON sub.backupIndexers;
      };

      script = lib.getExe arrProvision.prowlarrSync;
    };
  };
}
