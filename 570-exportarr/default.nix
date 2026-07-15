{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgGlobal = config.grapefruitMedia;
  cfg = cfgGlobal.exporters;
  ports = cfgGlobal.ports;
  tr = "${pkgs.coreutils}/bin/tr";
  grep = "${pkgs.gnugrep}/bin/grep";

  keyValidator = pkgs.writeShellScript "exportarr-key-valid" ''
    set -euo pipefail
    key=$(${tr} -d ' \n\r\t-' < "$1")
    len=''${#key}
    [ "$len" -ge 20 ] && [ "$len" -le 32 ] && printf '%s' "$key" | ${grep} -qE '^[a-zA-Z0-9]+$'
  '';

  mkWrapper =
    service: arrPort: exporterPort:
    pkgs.writeShellScript "exportarr-${service}-wrapper" ''
      set -euo pipefail
      key=$(${tr} -d ' \n\r\t-' < "''${CREDENTIALS_DIRECTORY}/api-key")
      exec ${pkgs.exportarr}/bin/exportarr ${service} \
        --url "http://127.0.0.1:${toString arrPort}" \
        --api-key "$key" \
        --port ${toString exporterPort} \
        --interface 127.0.0.1
    '';

  mkExporter =
    {
      service,
      portOption,
      arrPort,
      apiKeyFile,
    }:
    let
      exporterPort = ports.${portOption};
      wrapper = mkWrapper service arrPort exporterPort;
    in
    lib.mkIf (cfgGlobal.${service}.enable && cfg.enable) {
      systemd.services."prometheus-exportarr-${service}-exporter" = {
        description = "Prometheus Exportarr exporter for ${service}";
        after = [
          "${service}.service"
          "arr-secrets-generator.service"
          "network.target"
        ];
        wants = [ "${service}.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          User = "exportarr-${service}-exporter";
          Group = "exportarr-${service}-exporter";
          LoadCredential = [ "api-key:${apiKeyFile}" ];
          ExecCondition = "${keyValidator} %d/api-key";
          ExecStart = wrapper;
          Restart = "always";
          RestartSec = "10s";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          IPAddressAllow = [
            "localhost"
            "127.0.0.0/8"
            "::1/128"
          ];
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          UMask = "0077";
          WorkingDirectory = "/tmp";
        };
      };
    };
in
{
  config = lib.mkMerge [
    (mkExporter {
      service = "sonarr";
      portOption = "exportarr-sonarr";
      arrPort = ports.sonarr;
      apiKeyFile = cfgGlobal.secrets.arrApiKeyFile;
    })
    (mkExporter {
      service = "radarr";
      portOption = "exportarr-radarr";
      arrPort = ports.radarr;
      apiKeyFile = cfgGlobal.secrets.arrApiKeyFile;
    })
    (mkExporter {
      service = "prowlarr";
      portOption = "exportarr-prowlarr";
      arrPort = ports.prowlarr;
      apiKeyFile = cfgGlobal.secrets.arrApiKeyFile;
    })
    (lib.mkIf (cfgGlobal.lidarr.enable && cfg.lidarr.enable) (mkExporter {
      service = "lidarr";
      portOption = "exportarr-lidarr";
      arrPort = ports.lidarr;
      apiKeyFile = cfgGlobal.secrets.arrApiKeyFile;
    }))
  ];
}
