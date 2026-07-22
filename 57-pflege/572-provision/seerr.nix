# ---
# id: "provision-seerr"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Jellyseerr/Seerr-Erstsetup inkl. Jellyfin- und *arr-Verdrahtung"
# provides: [arr-sync-seerr.service]
# requires: [grapefruitMedia.provision]
# tags: [provisioning, jellyseerr, bootstrap]
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
  sub = prov.seerr;
  inherit (cfg) ports;
  inherit (cfg) locale;
  arrProvision = pkgs.callPackage ../../packages/arr-provision { };

  loopback = "127.0.0.1";

  seerrConfigJson = builtins.toJSON (
    {
      apiKeyFile = cfg.secrets.jellyseerrApiKeyFile;
      adminUsername = sub.jellyfin.adminUsername;
      adminPasswordFile = sub.jellyfin.adminPasswordFile;
      adminEmail =
        if sub.jellyfin.adminEmail != "" then sub.jellyfin.adminEmail else sub.jellyfin.adminUsername;
      jellyfinHost = loopback;
      jellyfinPort = ports.jellyfin;
      jellyfinUseSsl = false;
      jellyfinUrlBase = "";
      serverType = 2;
      locale = locale.language;
    }
    // lib.optionalAttrs cfg.sonarr.enable {
      sonarr = {
        enabled = true;
        name = "Sonarr";
        host = loopback;
        port = ports.sonarr;
        apiKeyFile = cfg.secrets.sonarrApiKeyFile;
        inherit (sub.sonarr) activeDirectory activeProfileName fallbackProfileName;
        isDefault = true;
        syncEnabled = true;
      };
    }
    // lib.optionalAttrs cfg.radarr.enable {
      radarr = {
        enabled = true;
        name = "Radarr";
        host = loopback;
        port = ports.radarr;
        apiKeyFile = cfg.secrets.radarrApiKeyFile;
        inherit (sub.radarr)
          activeDirectory
          activeProfileName
          fallbackProfileName
          minimumAvailability
          ;
        isDefault = true;
        syncEnabled = true;
      };
    }
  );

  anyTarget =
    (cfg.sonarr.enable || cfg.radarr.enable) && cfg.jellyfin.enable && cfg.jellyseerr.enable;
  active = cfg.enable && prov.enable && sub.enable && anyTarget;

  mediaRoot = cfg.storage.mediaRoot;
in
{
  options.grapefruitMedia.provision.seerr = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Jellyseerr deklarativ initialisieren und mit Jellyfin + Sonarr/Radarr verdrahten.";
    };

    jellyfin = {
      adminUsername = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Jellyfin-Admin fuer das initiale Seerr-Setup.";
      };
      adminPasswordFile = lib.mkOption {
        type = lib.types.str;
        default = cfg.secrets.jellyfinAdminPasswordFile;
        defaultText = lib.literalExpression "config.grapefruitMedia.secrets.jellyfinAdminPasswordFile";
        description = "Datei mit dem Jellyfin-Admin-Passwort.";
      };
      adminEmail = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "E-Mail fuer das Seerr-Setup (leer = adminUsername).";
      };
    };

    sonarr = {
      activeDirectory = lib.mkOption {
        type = lib.types.str;
        default = "${mediaRoot}/media/tv";
        defaultText = lib.literalExpression ''"''${storage.mediaRoot}/media/tv"'';
        description = "Root-Ordner fuer Serien (aus storage.mediaRoot abgeleitet, nicht hartkodiert).";
      };
      activeProfileName = lib.mkOption {
        type = lib.types.str;
        default = "German 1080p HEVC";
        description = "Bevorzugtes Sonarr-Qualitaetsprofil in Seerr.";
      };
      fallbackProfileName = lib.mkOption {
        type = lib.types.str;
        default = "English 1080p HEVC";
        description = "Fallback-Profil, wenn das bevorzugte fehlt.";
      };
    };

    radarr = {
      activeDirectory = lib.mkOption {
        type = lib.types.str;
        default = "${mediaRoot}/media/movies";
        defaultText = lib.literalExpression ''"''${storage.mediaRoot}/media/movies"'';
        description = "Root-Ordner fuer Filme (aus storage.mediaRoot abgeleitet).";
      };
      activeProfileName = lib.mkOption {
        type = lib.types.str;
        default = "German 1080p HEVC";
        description = "Bevorzugtes Radarr-Qualitaetsprofil in Seerr.";
      };
      fallbackProfileName = lib.mkOption {
        type = lib.types.str;
        default = "English 1080p HEVC";
        description = "Fallback-Profil, wenn das bevorzugte fehlt.";
      };
      minimumAvailability = lib.mkOption {
        type = lib.types.str;
        default = "released";
        description = "Radarr minimumAvailability fuer Seerr-Anfragen.";
      };
    };
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-seerr = {
      description = "Provision: Jellyseerr setup and *arr wiring";
      # Letzter Schritt der Kette: braucht Jellyfin-Bootstrap, Keys und Profile.
      after = [
        "arr-sync-jellyfin.service"
        "arr-sync-keys.service"
        "arr-sync-profiles.service"
        "seerr.service"
        "jellyfin.service"
      ]
      ++ lib.optional cfg.recyclarr.enable "recyclarr.service"
      ++ lib.optional cfg.sonarr.enable "sonarr.service"
      ++ lib.optional cfg.radarr.enable "radarr.service";
      wants = [
        "seerr.service"
        "jellyfin.service"
      ];
      wantedBy = [ "multi-user.target" ];

      startLimitIntervalSec = 600;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 3;
      };

      environment = {
        SEERR_HOST = loopback;
        SEERR_PORT = toString ports.jellyseerr;
        SEERR_CONFIG_JSON = seerrConfigJson;
      };

      script = lib.getExe arrProvision.seerrSync;
    };
  };
}
