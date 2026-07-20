# ---
# id: "jellyfin"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Jellyfin Media Server + Jellyseerr Request Manager"
# provides: [jellyfin, seerr]
# requires: [grapefruitMedia.storage, grapefruitMedia.hardware]
# ports: [5001, 5002]
# state_dir: "/var/lib/jellyfin /var/cache/jellyfin"
# tags: [jellyfin, jellyseerr, media, streaming, qsv]
# docs:
#   - docs/adr/5030-media-stack-factory-hardening.md
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  rebuildGuard = import ../lib/rebuild-guard.nix { inherit lib; };
  factory = import ../lib/service-factory.nix { inherit lib; };
  memory = import ../lib/memory-policy.nix {
    inherit lib;
    ramGB = cfg.hardware.ramGB;
  };
  cidrs = import ../lib/network-cidrs.nix { inherit lib; };

  cfgJellyfin = cfg.jellyfin;
  cfgJellyseerr = cfg.jellyseerr;
  domain = cfg.domain;
  portJellyfin = cfg.ports.jellyfin;
  portJellyseerr = cfg.ports.jellyseerr;
  locale = cfg.locale;
  localeLang = locale.language or "en";
  localeUi = lib.replaceStrings [ "_" ] [ "-" ] (locale.default or "en_US.UTF-8");
  localeCc = lib.toUpper (lib.substring 3 2 localeUi);
  # P0-1/P1-2: absolute Domain-URL nur wenn eine Domain gesetzt ist.
  # Ohne Domain leer -- Jellyfin nutzt dann Auto-Detection statt einer
  # kaputten https://jellyfin.null-URL.
  hasDomain = domain != null && domain != "";
  jellyfinUrl = if hasDomain then "https://jellyfin.${domain}" else "";
  vaapiDevice = cfg.hardware.renderDevice;

  jellyfinConfigSeeds = pkgs.runCommand "jellyfin-config-seeds" { } ''
    mkdir -p $out
    ${pkgs.gnused}/bin/sed \
      -e 's|@LOCALE_LANG@|${localeLang}|g' \
      -e 's|@LOCALE_CC@|${localeCc}|g' \
      -e 's|@LOCALE_UI@|${localeUi}|g' \
      -e 's|<MetadataPath>.*</MetadataPath>|<MetadataPath>${cfg.storage.metadataDir}/jellyfin</MetadataPath>|g' \
      ${./data/jellyfin-system.xml} > $out/system.xml
    ${pkgs.gnused}/bin/sed \
      -e 's|@JELLYFIN_URL@|${jellyfinUrl}|g' \
      -e 's|@JELLYFIN_PORT@|${toString portJellyfin}|g' \
      ${./data/jellyfin-network.xml} > $out/network.xml
    ${pkgs.gnused}/bin/sed \
      -e 's|@VAAPI_DEVICE@|${vaapiDevice}|g' \
      ${./data/jellyfin-encoding.xml} > $out/encoding.xml
    cp ${./data/jellyfin-dlna.xml} $out/dlna.xml
    cp ${./data/jellyfin-branding.xml} $out/branding.xml
  '';
in
{
  config = lib.mkMerge [
    {
      assertions = lib.optionals (cfg.enable && cfgJellyfin.enable) [
        {
          assertion = vaapiDevice != "";
          message = "[jellyfin] grapefruitMedia.hardware.renderDevice muss gesetzt sein (VA-API QuickSync).";
        }
      ];
    }
    (lib.mkIf (cfg.enable && cfgJellyfin.enable) (
      lib.mkMerge [
        {
          services.jellyfin = {
            enable = true;
            openFirewall = false;
            package = lib.mkIf (cfgJellyfin.package != null) cfgJellyfin.package;
          };

          fileSystems."/run/jellyfin-transcode" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [
              "size=6g"
              "mode=0750"
              "nosuid"
              "nodev"
            ];
          };

          systemd.tmpfiles.rules = [
            # Das Zustandsverzeichnis MUSS deklariert sein. Die Unit setzt
            # ReadWritePaths=/var/lib/jellyfin, und ReadWritePaths verlangt ein
            # EXISTIERENDES Verzeichnis -- fehlt es, scheitert schon das
            # Mount-Namespacing:
            #   "Failed to set up mount namespacing: /var/lib/jellyfin:
            #    No such file or directory"
            # Der Dienst kommt dann nie zum Start. Ohne diese Zeile ist das
            # Modul weder neuinstallations- noch wischfest.
            # 2026-07-20 auf q958 reproduziert (nach rm -rf /var/lib/jellyfin).
            # Gleiche Fehlerklasse wie bei den *arr-Diensten, siehe LEARNINGS L2.
            "d /var/lib/jellyfin 0700 jellyfin jellyfin -"
            "d /var/lib/jellyfin/config 0700 jellyfin jellyfin -"
            "d /var/cache/jellyfin 0700 jellyfin jellyfin -"
            "d /run/jellyfin-transcode 0750 jellyfin jellyfin -"
            "d ${cfg.storage.metadataDir}/jellyfin 0750 jellyfin media -"
          ];

          systemd.services.jellyfin.preStart = lib.mkBefore ''
            mkdir -p /var/lib/jellyfin/config
            SEED_DIR=${jellyfinConfigSeeds}
            for seed in system.xml network.xml encoding.xml dlna.xml branding.xml; do
              src="$SEED_DIR/$seed"
              dst="/var/lib/jellyfin/config/$seed"
              if [ ! -f "$src" ]; then
                echo "jellyfin: missing seed $seed" >&2
                exit 1
              fi
              if [ ! -f "$dst" ] || ! ${pkgs.diffutils}/bin/cmp -s "$src" "$dst"; then
                # Kein -o/-g: preStart laeuft bereits als User jellyfin und hat
                # kein CAP_CHOWN -> "install: cannot change ownership ...:
                # Operation not permitted", Unit endet in einer Crash-Loop.
                # Der Eigentuemer stimmt ohnehin, weil der Prozess jellyfin ist.
                install -m 0640 "$src" "$dst"
                echo "jellyfin: synced config seed $seed"
              fi
            done
          '';

          systemd.paths.jellyfin-transcode-cleanup = {
            description = "Jellyfin: Transcode-Cleanup bei Segment-Aktivität (max 1×/5min)";
            wantedBy = [ "multi-user.target" ];
            unitConfig = lib.mkMerge [
              rebuildGuard.pathUnitGuard
              {
                TriggerLimitBurst = 1;
                TriggerLimitIntervalSec = "5min";
              }
            ];
            pathConfig = {
              PathExists = "/run/jellyfin-transcode";
              PathChangedGlob = "/run/jellyfin-transcode/*";
              Unit = "jellyfin-transcode-cleanup.service";
              MakeDirectory = false;
            };
          };

          systemd.services.jellyfin-transcode-cleanup = {
            description = "Jellyfin: Transcode-Segmente RAM-adaptiv bereinigen";
            startLimitIntervalSec = 0;
            startLimitBurst = 0;
            path = with pkgs; [
              gawk
              findutils
              coreutils
            ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = pkgs.writeShellScript "jellyfin-transcode-cleanup" ''
                set -euo pipefail
                DIR=/run/jellyfin-transcode
                [ -d "$DIR" ] || exit 0

                MEM_TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
                MEM_AVAIL=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
                MEM_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))

                if [ "$MEM_PCT" -ge 80 ]; then
                  AGE=0
                  REASON="RAM $MEM_PCT%% Notfall"
                elif [ "$MEM_PCT" -ge 65 ]; then
                  AGE=15
                  REASON="RAM $MEM_PCT%% Druck"
                else
                  AGE=90
                  REASON="RAM $MEM_PCT%% Normal"
                fi

                if [ "$AGE" -eq 0 ]; then
                  COUNT=$(find "$DIR" -type f | wc -l)
                  find "$DIR" -type f -delete
                else
                  COUNT=$(find "$DIR" -type f -mmin +$AGE | wc -l)
                  find "$DIR" -type f -mmin +$AGE -delete
                fi
                find "$DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

                [ "$COUNT" -gt 0 ] && echo "jellyfin-transcode-cleanup: $COUNT Dateien ($REASON)"
                exit 0
              '';
              User = "root";
            };
          };

          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [
              intel-media-driver
              intel-compute-runtime-legacy1
              vpl-gpu-rt
            ];
          };

          users.users.jellyfin.extraGroups = [
            "video"
            "render"
            "media"
          ];

          systemd.services.jellyfin.serviceConfig.ExecStopPost = lib.mkOrder 100 [
            "+${pkgs.systemd}/bin/systemctl start jellyfin-transcode-cleanup.service"
          ];

          systemd.services.jellyfin.environment = {
            LIBVA_DRIVER_NAME = "iHD";
            LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
            VDPAU_DRIVER = "va_gl";
            OCL_ICD_VENDORS = "${pkgs.intel-compute-runtime-legacy1}/etc/OpenCL/vendors";
          };

          environment.systemPackages = with pkgs; [
            libva-utils
            intel-gpu-tools
          ];
        }
        (factory.mkStreamer {
          inherit config;
          name = "jellyfin";
          port = portJellyfin;
          useGPU = true;
          memoryPolicy = memory.jellyfin { };
          persistDirs = [
            "/var/lib/jellyfin"
            "/var/cache/jellyfin"
          ];
          readWritePaths = [
            "/var/lib/jellyfin"
            "/var/cache/jellyfin"
            "/run/jellyfin-transcode"
            "${cfg.storage.metadataDir}/jellyfin"
            "${cfg.storage.mediaRoot}/downloads"
          ];
          readOnlyPaths = [
            "${cfg.storage.mediaRoot}/media"
            "${pkgs.intel-media-driver}/lib"
            "${pkgs.intel-compute-runtime-legacy1}/lib"
            "/run/opengl-driver"
          ];
          extraSystemd = {
            IPAddressAllow = lib.mkForce (cidrs.trustedPrivateCidrs ++ [ cidrs.loopbackV4 ]);
            IPAddressDeny = lib.mkForce "any";
            RestrictAddressFamilies = lib.mkForce [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
              "AF_NETLINK"
            ];
          };
        })
      ]
    ))

    (lib.mkIf (cfg.enable && cfgJellyseerr.enable) (
      lib.mkMerge [
        {
          services.seerr = {
            enable = true;
            port = portJellyseerr;
            openFirewall = false;
            package = lib.mkIf (cfgJellyseerr.package != null) cfgJellyseerr.package;
          };
        }
        (factory.mkService {
          inherit config;
          name = "seerr";
          port = portJellyseerr;
          persistDirs = [ "/var/lib/seerr" ];
          readWritePaths = [ "/var/lib/seerr" ];
        })
        {
          systemd.services.seerr.serviceConfig.EnvironmentFile = lib.mkForce [
            "-${cfg.secrets.jellyseerrEnvFile}"
          ];
          systemd.services.seerr.serviceConfig.ExecStartPre =
            let
              walScript = pkgs.writeShellScript "seerr-wal-pragma" ''
                DB="/var/lib/seerr/db/db.sqlite3"
                [ -f "$DB" ] || exit 0
                ${pkgs.sqlite}/bin/sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null
                echo "seerr: SQLite WAL mode activated"
              '';
            in
            lib.mkBefore [ "+${walScript}" ];
        }
      ]
    ))
  ];
}
