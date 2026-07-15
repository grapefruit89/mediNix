{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgGlobal = config.grapefruitMedia;
  cfg = cfgGlobal.libreseerr;
  port = cfgGlobal.ports.libreseerr;
in
{
  config = lib.mkIf (cfgGlobal.enable && cfg.enable) {
    virtualisation.oci-containers.containers.libreseerr = {
      image = "ghcr.io/zamnzim/libreseerr:latest";
      ports = [ "127.0.0.1:${toString port}:5055" ];
      volumes = [
        "/var/lib/libreseerr:/app/config"
      ];
      environment = {
        TZ = config.time.timeZone;
      };
      extraOptions = [
        "--pull=always"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/libreseerr 0750 1000 1000 -"
    ];

    grapefruitMedia.persist.extraPaths = [ "/var/lib/libreseerr" ];
  };
}
