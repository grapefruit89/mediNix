{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.grapefruitMedia;
  isStandalone = cfg.ingress.enable && ((cfg.ingress.mode == "standalone") || (cfg.ingress.mode == "auto" && !config.services.caddy.enable));
  isGlobal = cfg.ingress.enable && ((cfg.ingress.mode == "global") || (cfg.ingress.mode == "auto" && config.services.caddy.enable));
in
{
  config = mkIf cfg.enable (mkMerge [
    (mkIf isStandalone {
      systemd.services.caddy-media = {
        description = "Isolated Standalone Caddy Ingress for Media Stack";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.caddy}/bin/caddy run --config ${pkgs.writeText "Caddyfile" ''
            http://localhost:80, http://127.0.0.1:80 {
              route /health {
                respond "OK" 200
              }
              route /save-usenet {
                reverse_proxy http://127.0.0.1:${toString cfg.ports.secrets-portal}
              }
              @secrets host media-secrets.local
              handle @secrets {
                reverse_proxy http://127.0.0.1:${toString cfg.ports.secrets-portal}
              }
              @portal host secrets-portal.local
              handle @portal {
                reverse_proxy http://127.0.0.1:${toString cfg.ports.secrets-portal}
              }
              # General fallback routing
              reverse_proxy http://127.0.0.1:${toString cfg.ports.jellyfin}
            }
            http://localhost:443, http://127.0.0.1:443 {
              respond "HTTPS OK" 200
            }
          ''}";

          # Capabilities hardening
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

          # Hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
          StateDirectory = "caddy-media";
          RuntimeDirectory = "caddy-media";
          User = "caddy-media";
          Group = "caddy-media";
        };
      };

      users.users.caddy-media = {
        isSystemUser = true;
        group = "caddy-media";
      };
      users.groups.caddy-media = {};
    })

    (mkIf isGlobal {
      services.caddy = {
        virtualHosts = {
          "${cfg.domain}" = {
            extraConfig = ''
              reverse_proxy http://127.0.0.1:${toString cfg.ports.jellyfin}
            '';
          };
          "media-secrets.local" = {
            extraConfig = ''
              reverse_proxy http://127.0.0.1:${toString cfg.ports.secrets-portal}
            '';
          };
        };
      };
    })
  ]);
}
