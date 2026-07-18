# ---
# id: "provision-jellyfin"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Jellyfin-Bootstrap: Admin, Bibliotheken, Metadaten-Sprache"
# provides: [arr-sync-jellyfin.service, jellyfin-intro-scan.service]
# requires: [grapefruitMedia.provision]
# tags: [provisioning, jellyfin, bootstrap]
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
  sub = prov.jellyfin;
  seerrCfg = prov.seerr;
  ports = cfg.ports;
  locale = cfg.locale;
  arrProvision = pkgs.callPackage ../packages/arr-provision { };

  active = cfg.enable && prov.enable && sub.enable && cfg.jellyfin.enable;

  baseEnv = {
    JELLYFIN_HOST = "127.0.0.1";
    JELLYFIN_PORT = toString ports.jellyfin;
    JELLYFIN_ADMIN_USER = seerrCfg.jellyfin.adminUsername;
    JELLYFIN_ADMIN_PASSWORD_FILE = seerrCfg.jellyfin.adminPasswordFile;
  };
in
{
  options.grapefruitMedia.provision.jellyfin = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Jellyfin-Admin, Bibliotheken (TV/Filme) und Metadaten-Sprache deklarativ anlegen.";
    };

    legacyPassword = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Einmaliges Alt-Passwort fuer die Migration auf das deklarative Secret.
        Nach erfolgreicher Migration wieder leeren.
      '';
    };

    libraryRefreshDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Intervall des automatischen Metadaten-Refresh in Tagen.";
    };

    enableChapterExtraction = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Kapitelbilder beim Bibliotheks-Scan extrahieren (Voraussetzung fuer Intro-Erkennung).";
    };

    enableIntroScan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Intro-/Kapitel-Scan direkt nach dem Bootstrap ausloesen.

        Default AUS -- der Scan ist sehr CPU- und RAM-intensiv und wuerde bei
        jedem Rebuild ueber die ganze Bibliothek laufen. Bei Bedarf manuell:
        `systemctl start jellyfin-intro-scan.service`
      '';
    };

    extraUsers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Benutzername in Jellyfin.";
            };
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = "Pfad zur Datei mit dem Passwort (nie Klartext in Nix).";
            };
          };
        }
      );
      default = [ ];
      description = "Weitere Jellyfin-Benutzer, die deklarativ angelegt werden.";
    };
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-jellyfin = {
      description = "Provision: Jellyfin admin + library bootstrap";
      after = [ "jellyfin.service" ];
      wants = [ "jellyfin.service" ];
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

      environment = baseEnv // {
        JELLYFIN_LEGACY_PASSWORD = sub.legacyPassword;
        JELLYFIN_TV_PATH = seerrCfg.sonarr.activeDirectory;
        JELLYFIN_MOVIES_PATH = seerrCfg.radarr.activeDirectory;
        JELLYFIN_LIBRARY_REFRESH_DAYS = toString sub.libraryRefreshDays;
        JELLYFIN_ENABLE_CHAPTER_EXTRACTION = if sub.enableChapterExtraction then "1" else "0";
        JELLYFIN_ENABLE_INTRO_SCAN = if sub.enableIntroScan then "1" else "0";
        JELLYFIN_METADATA_LANGUAGE = locale.language;
        JELLYFIN_METADATA_COUNTRY = lib.toUpper (lib.substring 3 2 locale.default);
        JELLYFIN_EXTRA_USERS_JSON = builtins.toJSON (
          map (u: {
            inherit (u) name;
            password_file = u.passwordFile;
          }) sub.extraUsers
        );
      };

      script = lib.getExe arrProvision.jellyfinSetup;
    };

    # Bewusst NICHT wantedBy -- laeuft nur auf Zuruf (schwer, lange Laufzeit).
    systemd.services.jellyfin-intro-scan = {
      description = "Jellyfin intro/chapter scan (on demand -- heavy CPU/RAM)";
      after = [ "jellyfin.service" ];
      wants = [ "jellyfin.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };

      environment = baseEnv // {
        JELLYFIN_INTRO_SCAN_ONLY = "1";
        JELLYFIN_ENABLE_INTRO_SCAN = "1";
      };

      script = lib.getExe arrProvision.jellyfinSetup;
    };
  };
}
