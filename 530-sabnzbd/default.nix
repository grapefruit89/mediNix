{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  memory = import ../lib/memory-policy.nix {
    inherit lib;
    ramGB = cfg.hardware.ramGB;
  };
  cfgSabnzbd = cfg.sabnzbd;
  portSabnzbd = cfg.ports.sabnzbd;
in
{
  config = lib.mkIf (cfg.enable && cfgSabnzbd.enable) {
    # If persist is enabled, hook paths
    grapefruitMedia.persist.extraPaths = [ "/var/lib/sabnzbd" ];

    services.sabnzbd = {
      enable = true;
      openFirewall = false;
      configFile = null;
      allowConfigWrite = true;
      settings = {
        misc = {
          port = portSabnzbd;
          host = "127.0.0.1";
          language = cfg.locale.language;
        };
      };
    };

    users = {
      groups = {
        media = { };
        sabnzbd = {};
      };
      users.sabnzbd = {
        group = "sabnzbd";
        isSystemUser = true;
        extraGroups = [ "media" ];
      };
    };

    systemd.services.sabnzbd.serviceConfig = lib.mkMerge [
      (memory.sabnzbd { })
      {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        UMask = "0002";
        RuntimeDirectory = "sabnzbd-tmp";
        RuntimeDirectoryMode = "0700";
        ReadWritePaths = [
          "/var/lib/sabnzbd"
          "${cfg.storage.mediaRoot}/downloads"
          "/run/sabnzbd-tmp"
        ];
      }
    ];

    systemd.services.sabnzbd.environment = {
      SABNZBD__MISC__TEMP_DIR = "/run/sabnzbd-tmp";
    };
  };
}
