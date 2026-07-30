# 522 -- SABnzbd VPN Kill-Switch (nftables type-route Marking + Policy-Routing +
# fail-closed Drop, v4+v6). Ersatz fuer das netns-usenet-confinement.
#
# NUR SABnzbd wird abgesichert. Sein GESAMTER Egress muss ueber cfg.vpn.interface;
# ist das Interface weg -> kein Byte raus (fail-closed). Der Dienst bleibt normal
# auf dem Host erreichbar (kein netns).
#
# OPT-IN via grapefruitMedia.vpn.killswitch.enable. Aus per Default -- scharf erst
# nach echtem Leak-Test mit aktivem Tunnel.
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
  uid = reg.uids.sabnzbd; # 5410 (number * 10)
  fwmark = 5410;
  rtTable = 5410;
  iface = vpn.interface;
in
{
  options.grapefruitMedia.vpn.killswitch.enable =
    lib.mkEnableOption "SABnzbd nftables VPN Kill-Switch (Ersatz fuer netns-Confinement)";

  config = lib.mkIf (cfgG.enable && cfgG.vpn.killswitch.enable && cfgG.sabnzbd.enable) {
    assertions = [
      {
        assertion = iface != "";
        message = "[medinix] vpn.interface ist leer -- der Kill-Switch braucht das VPN-Interface.";
      }
      {
        assertion = vpn.dns != [ ];
        message = "[medinix] vpn.dns ist leer -- SABnzbds DNS ginge am Tunnel vorbei (Leak).";
      }
    ];

    # SABnzbd sieht NUR die VPN-DNS-Server (privates resolv.conf).
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

    # Policy-Routing: markierte Pakete -> eigene Tabelle -> default via VPN.
    # oneshot, RemainAfterExit, laeuft VOR SABnzbd. Ist das Interface unten,
    # scheitert die Route -> Unit failt -> SABnzbd (requires) startet nicht.
    systemd.services.medinix-killswitch-route = {
      description = "medinix SABnzbd VPN policy routing (fwmark ${toString fwmark})";
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
          # unreachable-Fallback: markierte Pakete ohne VPN-Route werden verworfen,
          # nicht ueber die Haupttabelle geleakt (Defense-in-depth zum nft-Drop).
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

    # nftables: type-route Marking (loest die Re-Routung aus) + fail-closed Drop v4+v6.
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
  };
}
