# 522 -- SABnzbd VPN Kill-Switch (nftables type-route Marking + Policy-Routing +
# fail-closed Drop, v4+v6). Ersatz fuer das netns-usenet-confinement (521, deprecated).
# NUR SABnzbd. Egress zwingend ueber cfg.vpn.interface; Interface weg -> kein Byte
# raus (fail-closed). OPT-IN via grapefruitMedia.vpn.killswitch.enable.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgG = config.grapefruitMedia;
  inherit (cfgG) vpn;
  reg = import ../lib/registry.nix { inherit lib; };
  uid = reg.uids.sabnzbd;
  fwmark = 5410;
  rtTable = 5410;
  iface = vpn.interface;
  ks = cfgG.enable && cfgG.vpn.killswitch.enable && cfgG.sabnzbd.enable;
in
{
  options.grapefruitMedia.vpn.killswitch.enable =
    lib.mkEnableOption "SABnzbd nftables VPN Kill-Switch (Ersatz fuer netns-Confinement)";

  options.grapefruitMedia.security.dnsOverTls = lib.mkEnableOption ''
    system-weites DNS-over-TLS via systemd-resolved fuer den ganzen Stack --
    kein Klartext-DNS mehr. Empfohlen; Default aus (Host behaelt DNS-Strategie)
  '';

  config = lib.mkMerge [
    (lib.mkIf ks {
      assertions = [
        {
          assertion = iface != "";
          message = "[medinix] vpn.interface ist leer -- Kill-Switch braucht das VPN-Interface.";
        }
        {
          assertion = vpn.dns != [ ];
          message = "[medinix] vpn.dns ist leer -- SABnzbds DNS ginge am Tunnel vorbei (Leak).";
        }
        {
          assertion = (config.users.users.sabnzbd.uid or 0) == uid;
          message = "[medinix] SABnzbd laeuft nicht als UID 5410 -- skuid-Regel greift ins Leere, ALLES leakt. wireFixedUids = true setzen.";
        }
        {
          assertion = !cfgG.usenet-confinement.enable;
          message = "[medinix] killswitch UND usenet-confinement (netns) beide aktiv. netns MUSS aus: usenet-confinement.enable = false.";
        }
        {
          assertion =
            (config.networking.nftables.tables ? medinix-killswitch)
            && config.networking.nftables.tables.medinix-killswitch.family == "inet";
          message = "[medinix] Kill-Switch-nftables-Tabelle fehlt oder nicht family=inet (v4+v6).";
        }
        {
          assertion = config.systemd.services ? "medinix-killswitch-route";
          message = "[medinix] Policy-Routing-Unit fehlt.";
        }
        {
          assertion =
            lib.elem "medinix-killswitch-route.service" (config.systemd.services.sabnzbd.after or [ ])
            && lib.elem "medinix-killswitch-route.service" (config.systemd.services.sabnzbd.requires or [ ]);
          message = "[medinix] SABnzbd startet nicht nachweislich NACH dem Policy-Routing -- Boot-Race-Leak moeglich.";
        }
        {
          assertion = config.environment.etc ? "medinix-killswitch-resolv.conf";
          message = "[medinix] privates resolv.conf fuer SABnzbd fehlt -- DNS-Leak moeglich.";
        }
      ];

      environment.etc."medinix-killswitch-resolv.conf".text = lib.concatMapStrings (
        s: "nameserver ${s}\n"
      ) vpn.dns;

      systemd.services.sabnzbd = {
        after = [
          "nftables.service"
          "medinix-killswitch-route.service"
        ];
        requires = [ "medinix-killswitch-route.service" ];
        serviceConfig.BindReadOnlyPaths = [
          "/etc/medinix-killswitch-resolv.conf:/etc/resolv.conf"
        ];
      };

      systemd.services.medinix-killswitch-route = {
        description = "medinix SABnzbd VPN policy routing";
        after = [
          "network-online.target"
          "${iface}.service"
        ];
        wants = [ "network-online.target" ];
        before = [ "sabnzbd.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "medinix-killswitch-route-up" ''
            set -e
            IP=${pkgs.iproute2}/bin/ip
            $IP rule add fwmark ${toString fwmark} table ${toString rtTable} 2>/dev/null || true
            $IP -6 rule add fwmark ${toString fwmark} table ${toString rtTable} 2>/dev/null || true
            $IP route replace default dev ${iface} table ${toString rtTable}
            $IP -6 route replace default dev ${iface} table ${toString rtTable} 2>/dev/null || true
          '';
          ExecStop = pkgs.writeShellScript "medinix-killswitch-route-down" ''
            IP=${pkgs.iproute2}/bin/ip
            $IP rule del fwmark ${toString fwmark} table ${toString rtTable} 2>/dev/null || true
            $IP -6 rule del fwmark ${toString fwmark} table ${toString rtTable} 2>/dev/null || true
          '';
        };
      };

      networking.nftables.enable = true;
      networking.nftables.tables.medinix-killswitch = {
        family = "inet";
        content = ''
          chain mark {
            type route hook output priority mangle; policy accept;
            meta skuid ${toString uid} meta mark set ${toString fwmark}
          }
          chain killswitch {
            type filter hook output priority 0; policy accept;
            meta skuid ${toString uid} oifname "${iface}" accept
            meta skuid ${toString uid} drop
          }
        '';
      };
    })

    (lib.mkIf (cfgG.enable && cfgG.security.dnsOverTls) {
      services.resolved = {
        enable = true;
        dnssec = "true";
        dnsovertls = "true";
      };
    })
  ];
}
