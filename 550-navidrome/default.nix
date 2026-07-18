# ---
# id: "navidrome"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Navidrome Music Server (Subsonic API)"
# provides: [navidrome]
# requires: [grapefruitMedia.storage, grapefruitMedia.secrets]
# ports: [5009]
# state_dir: "/var/lib/navidrome"
# tags: [navidrome, music, subsonic]
# ---
{
  config,
  lib,
  ...
}:
let
  cfgGlobal = config.grapefruitMedia;
  cfg = cfgGlobal.navidrome;
  factory = import ../lib/service-factory.nix { inherit lib; };
  memory = import ../lib/memory-policy.nix {
    inherit lib;
    ramGB = cfgGlobal.hardware.ramGB;
  };
  domain = cfgGlobal.domain;
  # P0-1/P1-2: OIDC-DiscoveryUrl braucht eine echte Domain. Ohne Domain wird der
  # gesamte Oidc-Block weggelassen statt eine https://auth.null-URL zu bauen.
  hasDomain = domain != null && domain != "";
  port = cfgGlobal.ports.navidrome;
  mediaRoot = cfgGlobal.storage.mediaRoot;
  storageReady = cfgGlobal.storage.enable;
in
{
  config = lib.mkIf (cfgGlobal.enable && cfg.enable) (
    lib.mkMerge [
      {
        services.navidrome = {
          enable = true;
          package = lib.mkIf (cfgGlobal.navidrome.package != null) cfgGlobal.navidrome.package;
          settings = {
            Address = "127.0.0.1";
            Port = port;
            DataFolder = "/var/lib/navidrome";
            MusicFolder = lib.mkIf storageReady "${mediaRoot}/music";
          }
          // lib.optionalAttrs hasDomain {
            Oidc = {
              DiscoveryUrl = "https://auth.${domain}/.well-known/openid-configuration";
              AutoRegister = true;
              Scopes = "openid profile email";
            };
          };
        };

        # -Prefix: systemd ignoriert fehlende Datei → Navidrome startet ohne OIDC bis Secrets gesetzt
        systemd.services.navidrome.serviceConfig.EnvironmentFile = [
          "-${cfgGlobal.secrets.navidromeOidcFile}"
        ];
      }

      (factory.mkService {
        inherit config;
        name = "navidrome";
        inherit port;
        persistDirs = [ "/var/lib/navidrome" ];
        readWritePaths = [
          "/var/lib/navidrome"
        ]
        ++ lib.optionals storageReady [ "${mediaRoot}/music" ];
        memoryPolicy = memory.navidrome { };
      })

      (lib.mkIf storageReady {
        systemd.tmpfiles.rules = [ "d ${mediaRoot}/music 0775 navidrome media -" ];
      })
    ]
  );
}
