# ---
# id: "provision-settings"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "TRaSH-konforme Host-Settings in Sonarr/Radarr setzen"
# provides: [arr-sync-settings.service]
# requires: [grapefruitMedia.provision]
# tags: [provisioning, arr, trash]
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
  sub = prov.settings;
  ports = cfg.ports;
  arrProvision = pkgs.callPackage ../packages/arr-provision { };

  anyArr = cfg.sonarr.enable || cfg.radarr.enable;
  active = cfg.enable && prov.enable && sub.enable && anyArr;
in
{
  options.grapefruitMedia.provision.settings = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Sonarr/Radarr-Host-Settings nach TRaSH-Guidelines setzen
        (Sprache "Any", Repacks "doNotPrefer", Root-Folder).
      '';
    };
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-settings = {
      description = "Provision: declarative Radarr/Sonarr TRaSH host settings";
      after =
        lib.optional cfg.sonarr.enable "sonarr.service"
        ++ lib.optional cfg.radarr.enable "radarr.service"
        ++ lib.optional cfg.recyclarr.enable "recyclarr.service";
      wants =
        lib.optional cfg.sonarr.enable "sonarr.service"
        ++ lib.optional cfg.radarr.enable "radarr.service";
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
        ARR_HOST = "127.0.0.1";
        SYNC_SONARR = if cfg.sonarr.enable then "1" else "0";
        SYNC_RADARR = if cfg.radarr.enable then "1" else "0";
        SONARR_PORT = toString ports.sonarr;
        RADARR_PORT = toString ports.radarr;
        SONARR_KEY_FILE = cfg.secrets.sonarrApiKeyFile;
        RADARR_KEY_FILE = cfg.secrets.radarrApiKeyFile;
        SONARR_ROOT_FOLDER = prov.seerr.sonarr.activeDirectory;
        RADARR_ROOT_FOLDER = prov.seerr.radarr.activeDirectory;
      };

      script = lib.getExe arrProvision.arrSettingsSync;
    };
  };
}
