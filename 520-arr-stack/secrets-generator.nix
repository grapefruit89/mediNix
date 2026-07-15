{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.grapefruitMedia;
in
{
  config = mkIf cfg.enable {
    systemd.services.arr-secrets-generator = {
      description = "Idempotent Arr API Key Generator";
      after = [ "local-fs.target" ];
      before = [
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
        "lidarr.service"
        "readarr.service"
        "recyclarr.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "arr-secrets-generator" ''
          mkdir -p ${cfg.secrets.secretsDir}
          chmod 700 ${cfg.secrets.secretsDir}
          if [ ! -f ${cfg.secrets.arrApiKeyFile} ]; then
            ${pkgs.openssl}/bin/openssl rand -hex 16 > ${cfg.secrets.arrApiKeyFile}
            chmod 600 ${cfg.secrets.arrApiKeyFile}
          fi
          API_KEY=$(cat ${cfg.secrets.arrApiKeyFile})
          echo "SONARR__API_KEY=$API_KEY" > ${cfg.secrets.secretsDir}/sonarr.env
          echo "RADARR__API_KEY=$API_KEY" > ${cfg.secrets.secretsDir}/radarr.env
          echo "PROWLARR__API_KEY=$API_KEY" > ${cfg.secrets.secretsDir}/prowlarr.env
          echo "LIDARR__API_KEY=$API_KEY" > ${cfg.secrets.secretsDir}/lidarr.env
          echo "READARR__API_KEY=$API_KEY" > ${cfg.secrets.secretsDir}/readarr.env
          chmod 600 ${cfg.secrets.secretsDir}/*.env
        '';
      };
    };
  };
}
