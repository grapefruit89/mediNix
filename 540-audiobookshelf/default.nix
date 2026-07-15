# ---
# id: "audiobookshelf"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Audiobookshelf Audiobook/Podcast Server"
# provides: [audiobookshelf]
# requires: [grapefruitMedia.storage, grapefruitMedia.hardware]
# ports: [5008]
# state_dir: "/var/lib/audiobookshelf"
# tags: [audiobookshelf, audiobooks, streaming]
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgGlobal = config.grapefruitMedia;
  cfg = cfgGlobal.audiobookshelf;
  factory = import ../lib/service-factory.nix { inherit lib; };
  memory = import ../lib/memory-policy.nix {
    inherit lib;
    ramGB = cfgGlobal.hardware.ramGB;
  };
  port = cfgGlobal.ports.audiobookshelf;
  mediaRoot = cfgGlobal.storage.mediaRoot;
  storageReady = cfgGlobal.storage.enable;
in
{
  config = lib.mkIf (cfgGlobal.enable && cfg.enable) (
    lib.mkMerge [
      {
        services.audiobookshelf = {
          enable = true;
          host = "127.0.0.1";
          inherit port;
          group = "media";
        };

        users.users.audiobookshelf.extraGroups = lib.mkAfter [
          "media"
          "video"
          "render"
        ];

        hardware.graphics = lib.mkIf cfg.enableQuickSync {
          enable = lib.mkDefault true;
          extraPackages = with pkgs; [
            intel-media-driver
            intel-compute-runtime-legacy1
          ];
        };
      }

      (factory.mkService {
        inherit config;
        name = "audiobookshelf";
        inherit port;
        hardeningProfile = "node";
        persistDirs = [ "/var/lib/audiobookshelf" ];
        privateDevices = !cfg.enableQuickSync;
        readWritePaths = [
          "/var/lib/audiobookshelf"
        ]
        ++ lib.optionals storageReady [
          "${mediaRoot}/books"
          "${mediaRoot}/audiobooks"
          "${mediaRoot}/podcasts"
        ];
        memoryPolicy = memory.audiobookshelf { };
        extraSystemd = {
          Restart = lib.mkForce "on-failure";
        }
        // lib.optionalAttrs cfg.enableQuickSync {
          PrivateDevices = lib.mkForce false;
          DeviceAllow = [
            "/dev/dri rw"
            "/dev/dri/card0 rw"
            "/dev/dri/renderD128 rw"
          ];
        };
      })

      (lib.mkIf cfg.enableQuickSync {
        systemd.services.audiobookshelf.environment = {
          LIBVA_DRIVER_NAME = "iHD";
          LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
        };
      })

      (lib.mkIf storageReady {
        systemd.tmpfiles.rules = [
          "d ${mediaRoot}/books 0775 audiobookshelf media -"
          "d ${mediaRoot}/audiobooks 0775 audiobookshelf media -"
          "d ${mediaRoot}/podcasts 0775 audiobookshelf media -"
        ];
      })
    ]
  );
}
