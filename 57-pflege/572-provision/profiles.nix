# ---
# id: "provision-profiles"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "TRaSH-Quality-Profile auf die bestehende Bibliothek anwenden"
# provides: [arr-sync-profiles.service]
# requires: [grapefruitMedia.provision]
# tags: [provisioning, arr, trash, profiles]
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
  sub = prov.profiles;
  inherit (cfg) ports;
  arrProvision = pkgs.callPackage ../../packages/arr-provision { };

  anyArr = cfg.sonarr.enable || cfg.radarr.enable;
  active = cfg.enable && prov.enable && sub.enable && anyArr;
in
{
  options.grapefruitMedia.provision.profiles = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Bereits vorhandenen Serien/Filmen die von Recyclarr angelegten
        Quality-Profile zuweisen (Bulk-Edit). Ohne diesen Schritt gelten die
        neuen Profile nur fuer kuenftige Eintraege.
      '';
    };
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-profiles = {
      description = "Provision: assign quality profiles to existing library";
      # Muss NACH keys/settings laufen -- die Profile existieren erst, wenn
      # Recyclarr durch ist und die API-Keys stimmen.
      after =
        lib.optional cfg.sonarr.enable "sonarr.service"
        ++ lib.optional cfg.radarr.enable "radarr.service"
        ++ lib.optional cfg.recyclarr.enable "recyclarr.service"
        ++ [
          "arr-sync-keys.service"
          "arr-sync-settings.service"
        ];
      wants =
        lib.optional cfg.sonarr.enable "sonarr.service"
        ++ lib.optional cfg.radarr.enable "radarr.service"
        ++ lib.optional cfg.recyclarr.enable "recyclarr.service";
      wantedBy = [ "multi-user.target" ];

      startLimitIntervalSec = 600;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Restart = "on-failure";
        RestartSec = "60s";
        StartLimitBurst = 3;
      };

      environment = {
        ARR_HOST = "127.0.0.1";
        SYNC_SONARR = if cfg.sonarr.enable then "1" else "0";
        SYNC_RADARR = if cfg.radarr.enable then "1" else "0";
        SONARR_PORT = toString ports.sonarr;
        RADARR_PORT = toString ports.radarr;
        SONARR_KEY_FILE = cfg.secrets.sonarrApiKeyFile;
        RADARR_KEY_FILE = cfg.secrets.radarrApiKeyFile;
      };

      script = lib.getExe arrProvision.profileSync;
    };
  };
}
