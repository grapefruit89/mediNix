# ---
# id: "provision-locale"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Jellyfin-/SABnzbd-Locale und SABnzbd-Kategorien aus der Nix-SSoT setzen"
# provides: [arr-sync-locale.service]
# requires: [grapefruitMedia.provision, grapefruitMedia.locale]
# tags: [provisioning, locale, sabnzbd, jellyfin]
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
  sub = prov.locale;
  arrProvision = pkgs.callPackage ../packages/arr-provision { };

  anyEnabled = cfg.jellyfin.enable || cfg.sabnzbd.enable;
  active = cfg.enable && prov.enable && sub.enable && anyEnabled;

  # Kategorien muessen zu den Download-Client-Kategorien passen (siehe
  # download-clients.nix), sonst landen Downloads im falschen Ordner.
  defaultCategories = [
    { name = "tv"; dir = "tv"; newzbin = "tv"; order = 2; }
    { name = "movies"; dir = "movies"; newzbin = "movies"; order = 1; }
    { name = "audiobooks"; dir = "audiobooks"; newzbin = "audiobooks"; order = 3; }
    { name = "music"; dir = "music"; newzbin = "music"; order = 5; }
  ];

  mkCategoryIni =
    cats:
    lib.concatMapStringsSep "\n" (cat: ''
      [[${cat.name}]]
      name = ${cat.name}
      order = ${toString cat.order}
      pp = ${cat.pp}
      script = ${cat.script}
      dir = ${cat.dir}
      newzbin = ${cat.newzbin}
      priority = ${toString cat.priority}
    '') cats;

  categoriesIniBlock = "[categories]\n${mkCategoryIni sub.sabnzbd.categories}";
in
{
  options.grapefruitMedia.provision.locale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Sprache/Locale in Jellyfin und SABnzbd aus grapefruitMedia.locale setzen
        und die SABnzbd-Kategorien anlegen.
      '';
    };

    sabnzbd.categories = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Kategoriename (muss zur *arr-Download-Kategorie passen).";
            };
            dir = lib.mkOption {
              type = lib.types.str;
              description = "Zielordner relativ zum SABnzbd-Download-Verzeichnis.";
            };
            newzbin = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Indexer-Kategoriename.";
            };
            order = lib.mkOption {
              type = lib.types.int;
              default = 0;
              description = "Reihenfolge in der SABnzbd-Oberflaeche.";
            };
            pp = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Post-Processing-Stufe (leer = Default).";
            };
            script = lib.mkOption {
              type = lib.types.str;
              default = "Default";
              description = "Post-Processing-Script.";
            };
            priority = lib.mkOption {
              type = lib.types.int;
              default = -100;
              description = "Queue-Prioritaet (-100 = Standard).";
            };
          };
        }
      );
      default = defaultCategories;
      description = ''
        SABnzbd-Kategorien, deklarativ definiert und per Sync eingepflegt.
        Muessen zu provision.downloadClients.<svc>.category passen.
      '';
    };
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-locale = {
      description = "Provision: media locale sync (Jellyfin + SABnzbd)";
      after =
        lib.optional cfg.jellyfin.enable "jellyfin.service"
        ++ lib.optional cfg.sabnzbd.enable "sabnzbd.service";
      wants =
        lib.optional cfg.jellyfin.enable "jellyfin.service"
        ++ lib.optional cfg.sabnzbd.enable "sabnzbd.service";
      wantedBy = [ "multi-user.target" ];

      startLimitIntervalSec = 300;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 3;
      };

      environment = {
        TARGET_LANG = cfg.locale.language;
        TARGET_LOCALE = cfg.locale.default;
        CATEGORIES_INI = categoriesIniBlock;
        SAB_KEY_FILE = cfg.secrets.sabnzbdApiKeyFile;
        SYNC_JELLYFIN = if cfg.jellyfin.enable then "1" else "0";
        SYNC_SABNZBD = if cfg.sabnzbd.enable then "1" else "0";
      };

      script = lib.getExe arrProvision.localeSync;
    };
  };
}
