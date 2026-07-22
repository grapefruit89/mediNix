# ---
# id: "provision-keys"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "API-Keys deklarativ in die *arr/SABnzbd-Configs injizieren"
# provides: [arr-sync-keys.service]
# requires: [grapefruitMedia.provision, grapefruitMedia.secrets]
# tags: [provisioning, secrets, arr]
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
  sub = prov.keys;
  inherit (cfg) ports;
  arrProvision = pkgs.callPackage ../../packages/arr-provision { };
  provision = import ../../lib/provision-unit.nix { inherit lib; };

  anyArr = cfg.sonarr.enable || cfg.radarr.enable || cfg.prowlarr.enable || cfg.sabnzbd.enable;
  active = cfg.enable && prov.enable && sub.enable && anyArr;

  svcDep =
    lib.optional cfg.sonarr.enable "sonarr.service"
    ++ lib.optional cfg.radarr.enable "radarr.service"
    ++ lib.optional cfg.prowlarr.enable "prowlarr.service"
    ++ lib.optional cfg.sabnzbd.enable "sabnzbd.service";
in
{
  options.grapefruitMedia.provision.keys = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        API-Keys aus den secrets.*ApiKeyFile-Pfaden in die App-Configs schreiben
        und die Dienste neu starten. Greift nur bei provision.enable = true.
      '';
    };
  };

  config = lib.mkIf active (
    provision.mkProvisionUnit {
      name = "arr-sync-keys";
      description = "Provision: apply declarative *arr/SABnzbd API keys";
      after = svcDep;
      wants = svcDep;

      environment = {
        ARR_HOST = "127.0.0.1";
        SYNC_SONARR = if cfg.sonarr.enable then "1" else "0";
        SYNC_RADARR = if cfg.radarr.enable then "1" else "0";
        SYNC_PROWLARR = if cfg.prowlarr.enable then "1" else "0";
        SYNC_SABNZBD = if cfg.sabnzbd.enable then "1" else "0";
        SONARR_PORT = toString ports.sonarr;
        RADARR_PORT = toString ports.radarr;
        PROWLARR_PORT = toString ports.prowlarr;
        SONARR_KEY_FILE = cfg.secrets.sonarrApiKeyFile;
        RADARR_KEY_FILE = cfg.secrets.radarrApiKeyFile;
        PROWLARR_KEY_FILE = cfg.secrets.prowlarrApiKeyFile;
        SABNZBD_KEY_FILE = cfg.secrets.sabnzbdApiKeyFile;
      };

      script = lib.getExe arrProvision.arrKeysSync;
    }
  );
}
