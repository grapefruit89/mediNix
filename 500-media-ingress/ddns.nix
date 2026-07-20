# ---
# id: "media-ddns"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Standalone dynamischer DNS-Sync (LAN + optional WAN) via ddclient"
# provides: [services.ddclient]
# requires: [grapefruitMedia.dns, grapefruitMedia.domain]
# tags: [dns, ddns, cloudflare, portability]
# docs:
#   - modules/50-media/docs/network-topology.md
# ---
# Nur aktiv bei dns.mode = "standalone" und dns.ddns.enable.
# Im Default-Modus "host" macht das der Host (z.B. 10-network/1091-ddclient.nix).
#
# Zwei Jobs, exakt die Pfade aus docs/network-topology.md:
#   LAN  (Pfad 2): *.domain + @  -> aktuelle LAN-IP, ermittelt ueber den Kernel
#                  (`ip route get 1.1.1.1`). Hardware- und subnetz-agnostisch:
#                  egal ob 192.168.x, 172.16.x oder 10.0.x, egal wie die NIC heisst.
#   WAN  (Pfad 1): edge-Namen   -> oeffentliche IP (nur wenn kein Router-DynDNS).
#
# "Schalter statt Timer": ddclient laeuft als Daemon und feuert den API-Call nur
# bei echter IP-Aenderung (Delta) -- kein Cronjob, keine Cloudflare-Rate-Limits.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  dnsCfg = cfg.dns;
  inherit (dnsCfg) ddns;

  inherit (cfg) domain;
  hasDomain = domain != null && domain != "";

  tiers = import ../lib/service-tiers.nix { inherit lib; };

  enabledServices = lib.filter (n: n != "") [
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

  derived = import ../lib/dns.nix {
    inherit
      lib
      tiers
      domain
      enabledServices
      ;
    inherit (dnsCfg) hostnames;
  };

  active = cfg.enable && dnsCfg.mode == "standalone" && ddns.enable;

  zone = if ddns.zone != null then ddns.zone else domain;

  credName = "CF_DDNS_API_TOKEN";
  useCred = ddns.tokenCredential != null;
  passwordFile = if useCred then "/run/credentials/ddclient.service/${credName}" else ddns.tokenFile;

  # Kernel fragen, mit welcher lokalen Quell-IP das Internet erreicht wird.
  lanIpCmd = "${pkgs.iproute2}/bin/ip route get 1.1.1.1 | ${pkgs.gnused}/bin/sed -n \"s/.*src \\([0-9.]*\\).*/\\1/p\"";

  wanJobBlock = lib.optionalString (ddns.wanJob && derived.edgeNames != [ ]) ''

    # --- Job WAN (Pfad 1): Edge-Dienste auf die oeffentliche IP ---
    use=web, web=cloudflare
    ${lib.concatStringsSep ", " derived.edgeNames}
  '';
in
{
  config = lib.mkIf active {
    assertions = [
      {
        assertion = hasDomain;
        message = ''
          [50-media/ddns] dns.ddns.enable = true erfordert grapefruitMedia.domain.
          Ohne Domain gibt es keine L2-Namen, die synchronisiert werden koennten
          (L1 .local braucht kein DDNS -- das macht mDNS).
        '';
      }
      {
        assertion = (ddns.tokenCredential != null) != (ddns.tokenFile != null);
        message = ''
          [50-media/ddns] Genau eine Token-Quelle setzen:
          dns.ddns.tokenCredential (systemd-creds, bevorzugt) ODER dns.ddns.tokenFile
          (z.B. sops-nix). Niemals beides und niemals keines -- der Token darf nie
          im Nix-Store landen.
        '';
      }
    ];

    services.ddclient = {
      enable = true;
      protocol = "cloudflare";
      inherit zone;
      # Cloudflare-API-Tokens erwarten "token" als Dummy-Username.
      username = "token";
      inherit passwordFile;
      inherit (ddns) interval;

      # Bewusst KEIN globales usev4/domains -- beide Jobs stehen in extraConfig,
      # sonst wuerde das Modul die Job-Trennung ueberschreiben.
      extraConfig = ''
        # --- Job LAN (Pfad 2): Wildcard + Root auf die aktuelle LAN-IP ---
        # Kernel-Routing statt NIC-Name: portabel ueber Hardware und Subnetze.
        use=cmd, cmd='${lanIpCmd}'
        *.${domain}, @
        ${wanJobBlock}
      '';
    };

    systemd.services.ddclient = {
      serviceConfig = lib.mkIf useCred {
        LoadCredentialEncrypted = "${credName}:${ddns.tokenCredential}";
      };
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
  };
}
