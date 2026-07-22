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
#   - 50-core/archiv/grok-review.md
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
  # Frueher stand hier eine handgepflegte Liste aller UI-Dienste -- dieselbe
  # Information wie im Ingress und in der Port-Tabelle, dreifach geschrieben.
  # Ein neuer Dienst, den jemand hier zu ergaenzen vergass, war erreichbar und
  # trotzdem unauffindbar: Port da, vHost da, aber kein {name}.local.
  # Jetzt kommt die Menge aus der Registry (ui = true).
  registry = import ../lib/registry.nix { inherit lib; };
  enabledNames = lib.filter (n: cfg.${n}.enable or false) registry.uiServices;

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

    # Ohne diese Pruefung meldet der Dienst Erfolg, obwohl KEIN einziger Alias
    # publiziert wurde: die avahi-publish-Prozesse laufen im Hintergrund, und
    # 'wait' ohne lebende Kinder liefert 0. Genau das ist am 2026-07-20 auf q958
    # passiert -- alle Publishes scheiterten mit "Failed to create entry group:
    # Not permitted", die Unit lief nach 48ms mit status=0/SUCCESS aus, und
    # Restart=on-failure griff deshalb NIE. Ein Dienst, der seinen eigenen
    # Misserfolg nicht melden kann, ist schlimmer als einer, der abstuerzt.
    sleep 2
    alive=0
    for p in $pids; do
      if kill -0 "$p" 2>/dev/null; then
        alive=$((alive + 1))
      fi
    done

    if [ "$alive" -eq 0 ]; then
      echo "grapefruit-media-mdns: kein einziger Alias konnte publiziert werden." >&2
      echo "  Haeufigste Ursache: services.avahi.publish.userServices = false." >&2
      exit 1
    fi

    echo "grapefruit-media-mdns: $alive Alias(e) aktiv"

    # Unit am Leben halten; Neustart bei Netzwechsel ueber die path-Unit.
    wait
  '';
in
{
  config = lib.mkIf (cfg.enable && mdns.enable && enabledNames != [ ]) {
    services.avahi = {
      enable = true;
      # Clients on this host resolve *.local via nss-mdns.
      nssmdns4 = lib.mkDefault true;
      inherit (mdns) openFirewall;
      publish = {
        enable = true;
        addresses = true;
        # PFLICHT fuer avahi-publish: steuert disable-user-service-publishing
        # in avahi-daemon.conf (nixpkgs avahi-daemon.nix:39). Ohne das wird
        # JEDER Client-Publish abgewiesen -- auch als root:
        #   "Failed to create entry group: Not permitted"
        # Auf q958 am 2026-07-20 reproduziert und mit diesem Schalter behoben.
        userServices = true;
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
