# ---
# id: "media-mdns"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Phase B P1-1 -- Avahi mDNS: {service}.local -> LAN-IP fuer alle UI-Dienste"
# provides: [services.avahi, grapefruit-media-mdns-aliases.service]
# requires: [grapefruitMedia.discovery.mdns]
# tags: [mdns, avahi, discovery, lan]
# docs:
#   - modules/50-media/grok-review.md
#   - modules/50-media/README.md
# ---
# Fallstrick (UNVERHANDELBAR):
#   .local = NUR Multicast im LAN. NIEMALS Cloudflare, NIEMALS Unicast-Rewrite.
#   Publish-Ziel = LAN-IP des Hosts (nicht 127.0.0.1 -- sonst nur Loopback-Clients).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  mdns = cfg.discovery.mdns;

  # Gleiche UI-Menge wie Ingress (kein recyclarr/exportarr).
  # optionalString liefert "" wenn aus -- filter auf nicht-leer.
  enabledNames = lib.filter (n: n != "") [
    (lib.optionalString cfg.jellyfin.enable "jellyfin")
    (lib.optionalString cfg.jellyseerr.enable "jellyseerr")
    (lib.optionalString cfg.sonarr.enable "sonarr")
    (lib.optionalString cfg.radarr.enable "radarr")
    (lib.optionalString cfg.readarr.enable "readarr")
    (lib.optionalString cfg.prowlarr.enable "prowlarr")
    (lib.optionalString cfg.sabnzbd.enable "sabnzbd")
    (lib.optionalString cfg.audiobookshelf.enable "audiobookshelf")
    (lib.optionalString cfg.navidrome.enable "navidrome")
    (lib.optionalString cfg.lidarr.enable "lidarr")
  ];

  # avahi-publish -a haelt den Alias solange der Prozess laeuft.
  # IP dynamisch aus dem Default-Route-Interface (kein hardcodiertes 192.168.x).
  aliasScript = pkgs.writeShellScript "grapefruit-media-mdns-aliases" ''
    set -euo pipefail

    get_lan_ip() {
      # Prefer source IP of default route (works with multi-homing better than "first global").
      ip=$(${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' \
        || true)
      if [ -z "''${ip:-}" ]; then
        ip=$(${pkgs.iproute2}/bin/ip -4 -o addr show scope global \
          | ${pkgs.gawk}/bin/awk '{ split($4, a, "/"); print a[1]; exit }' \
          || true)
      fi
      printf '%s' "''${ip:-}"
    }

    IP=""
    for _try in 1 2 3 4 5 6 7 8 9 10; do
      IP=$(get_lan_ip)
      if [ -n "$IP" ]; then
        break
      fi
      sleep 1
    done

    if [ -z "$IP" ]; then
      echo "grapefruit-media-mdns: no LAN IPv4 after retries -- skip publish" >&2
      exit 1
    fi

    echo "grapefruit-media-mdns: publishing aliases -> $IP"

    pids=""
    ${lib.concatMapStrings (name: ''
      ${pkgs.avahi}/bin/avahi-publish -a -R ${name}.local "$IP" &
      pids="$pids $!"
    '') enabledNames}

    cleanup() {
      for p in $pids; do
        kill "$p" 2>/dev/null || true
      done
    }
    trap cleanup EXIT INT TERM

    # Keep unit alive; restart via systemd if network changes (see path/network targets).
    wait
  '';
in
{
  config = lib.mkIf (cfg.enable && mdns.enable && enabledNames != [ ]) {
    services.avahi = {
      enable = true;
      # Clients on this host resolve *.local via nss-mdns.
      nssmdns4 = lib.mkDefault true;
      openFirewall = mdns.openFirewall;
      publish = {
        enable = true;
        addresses = true;
        # workstation/hinfo optional -- addresses reichen fuer Alias-Publish.
      };
    };

    systemd.services.grapefruit-media-mdns-aliases = {
      description = "grapefruitMedia mDNS aliases ({service}.local -> LAN-IP)";
      after = [
        "avahi-daemon.service"
        "network-online.target"
      ];
      wants = [
        "avahi-daemon.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
      # Neu-Publish wenn Carrier/Adresse wechseln (dynamische LAN-IP, kein Hardcode).
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${aliasScript}";
        Restart = "on-failure";
        RestartSec = "5s";
        # Avahi client needs D-Bus + network; keep sandbox light.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
      };
    };

    # Re-publish when leases change (PathChanged startet nur inactive units --
    # deshalb oneshot restart, damit laufende avahi-publish-Prozesse neu binden).
    systemd.services.grapefruit-media-mdns-aliases-restart = {
      description = "Restart media mDNS aliases after network change";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl restart grapefruit-media-mdns-aliases.service";
      };
    };

    systemd.paths.grapefruit-media-mdns-aliases-refresh = {
      description = "Watch network leases for media mDNS re-publish";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = "/run/systemd/netif/leases";
        Unit = "grapefruit-media-mdns-aliases-restart.service";
        MakeDirectory = false;
      };
    };
  };
}
