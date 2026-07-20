# ---
# id: "provision-download-clients"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "SABnzbd als Download-Client in allen aktiven *arr registrieren"
# provides: [arr-sync-download-clients.service]
# requires: [grapefruitMedia.provision]
# tags: [provisioning, arr, sabnzbd]
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
  sub = prov.downloadClients;
  inherit (cfg) ports;
  arrProvision = pkgs.callPackage ../packages/arr-provision { };

  loopback = "127.0.0.1";

  arrTargets = lib.filterAttrs (_: v: v.enabled) {
    sonarr = {
      enabled = cfg.sonarr.enable;
      port = ports.sonarr;
      apiVersion = "v3";
      category = sub.sonarr.category;
      apiKeyFile = cfg.secrets.sonarrApiKeyFile;
    };
    radarr = {
      enabled = cfg.radarr.enable;
      port = ports.radarr;
      apiVersion = "v3";
      category = sub.radarr.category;
      apiKeyFile = cfg.secrets.radarrApiKeyFile;
    };
    readarr = {
      enabled = cfg.readarr.enable;
      port = ports.readarr;
      apiVersion = "v1";
      category = sub.readarr.category;
      apiKeyFile = cfg.secrets.readarrApiKeyFile;
    };
    lidarr = {
      enabled = cfg.lidarr.enable;
      port = ports.lidarr;
      apiVersion = "v1";
      category = sub.lidarr.category;
      apiKeyFile = cfg.secrets.lidarrApiKeyFile;
    };
  };

  targetsJson = builtins.toJSON (
    lib.mapAttrsToList (name: t: {
      inherit name;
      inherit (t)
        port
        apiVersion
        category
        apiKeyFile
        ;
    }) arrTargets
  );

  active = cfg.enable && prov.enable && sub.enable && cfg.sabnzbd.enable && arrTargets != { };

  mkCategoryOption =
    svc: default:
    lib.mkOption {
      type = lib.types.str;
      inherit default;
      description = "SABnzbd-Kategorie fuer ${svc}-Downloads.";
    };
in
{
  options.grapefruitMedia.provision.downloadClients = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "SABnzbd deklarativ als Download-Client in den *arr registrieren.";
    };

    sonarr.category = mkCategoryOption "Sonarr" "tv";
    radarr.category = mkCategoryOption "Radarr" "movies";
    readarr.category = mkCategoryOption "Readarr" "audiobooks";
    lidarr.category = mkCategoryOption "Lidarr" "music";
  };

  config = lib.mkIf active {
    systemd.services.arr-sync-download-clients = {
      description = "Provision: register SABnzbd as download client in *arr";
      after = [ "sabnzbd.service" ] ++ lib.mapAttrsToList (name: _: "${name}.service") arrTargets;
      wants = [ "sabnzbd.service" ];
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
        SAB_HOST = loopback;
        SAB_PORT = toString ports.sabnzbd;
        SAB_KEY_FILE = cfg.secrets.sabnzbdApiKeyFile;
        HOST_BRIDGE = loopback;
        TARGETS_JSON = targetsJson;
      };

      script = lib.getExe arrProvision.downloadClients;
    };
  };
}
