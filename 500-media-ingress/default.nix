# ---
# id: "media-ingress"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Chamaelon-Ingress -- standalone caddy-media oder global Caddy vHosts (L1 .local + L2 domain)"
# provides: [caddy-media (standalone), services.caddy.virtualHosts (global)]
# requires: [grapefruitMedia.ingress, grapefruitMedia.domain, grapefruitMedia.discovery.mdns]
# tags: [caddy, ingress, reverse-proxy, mdns]
# docs:
#   - modules/50-media/grok-review.md
#   - modules/50-media/README.md
# ---
# Phase B (2026-07-15):
#   P1-1 mDNS        -- ./mdns.nix (Avahi + {service}.local -> LAN-IP)
#   P0-3 Doppel-Host -- immer {name}.local, plus {name}.{domain} wenn domain gesetzt
#   P1-7 Global      -- vHost-Keys fuer .local (http://) und Domain (ACME-faehig)
#
# Fallstrick: .local nie in Cloudflare. domain nie auf .local enden lassen.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  domain = cfg.domain;
  hasDomain = domain != null && domain != "";
  ports = cfg.ports;
  auth = cfg.ingress.auth;
  tlsMode = cfg.ingress.tls.mode;
  tlsOn = tlsMode != "off";

  isStandalone =
    cfg.ingress.enable
    && (
      (cfg.ingress.mode == "standalone")
      || (cfg.ingress.mode == "auto" && !config.services.caddy.enable)
    );

  isGlobal =
    cfg.ingress.enable
    && (
      (cfg.ingress.mode == "global")
      || (cfg.ingress.mode == "auto" && config.services.caddy.enable)
    );

  # Bug1 Fix: if/else null (optionalAttrs false == {} filterte nie).
  enabledServices = lib.filterAttrs (_: v: v != null) {
    jellyfin = if cfg.jellyfin.enable then { port = ports.jellyfin; } else null;
    jellyseerr = if cfg.jellyseerr.enable then { port = ports.jellyseerr; } else null;
    sonarr = if cfg.sonarr.enable then { port = ports.sonarr; } else null;
    radarr = if cfg.radarr.enable then { port = ports.radarr; } else null;
    readarr = if cfg.readarr.enable then { port = ports.readarr; } else null;
    prowlarr = if cfg.prowlarr.enable then { port = ports.prowlarr; } else null;
    sabnzbd = if cfg.sabnzbd.enable then { port = ports.sabnzbd; } else null;
    audiobookshelf = if cfg.audiobookshelf.enable then { port = ports.audiobookshelf; } else null;
    navidrome = if cfg.navidrome.enable then { port = ports.navidrome; } else null;
    lidarr = if cfg.lidarr.enable then { port = ports.lidarr; } else null;
  };

  hasForwardAuth = auth.mode == "forward-auth";
  hasSkipPaths = hasForwardAuth && auth.skipPaths != [ ];
  skipPathsStr = lib.concatStringsSep " " auth.skipPaths;

  # P0-3: Host-Liste pro Service -- L1 immer, L2 nur bei Domain.
  # Caddy: @name host a [b ...]
  hostList =
    name:
    lib.concatStringsSep " " (
      [ "${name}.local" ] ++ lib.optional hasDomain "${name}.${domain}"
    );

  mkForwardAuthBlock = ''
    forward_auth ${auth.forwardAuthUpstream} {
      uri ${auth.forwardAuthUri}
      copy_headers Remote-User Remote-Email Remote-Groups X-Auth-Request-User X-Auth-Request-Email
    }
  '';

  # Inneres Handle (Auth + Proxy) -- Host-Matcher liegt aussen.
  mkProxyBody =
    svc:
    let
      proxy = "reverse_proxy http://127.0.0.1:${toString svc.port}";
    in
    if hasSkipPaths then
      ''
        @skip path ${skipPathsStr}
        handle @skip {
          ${proxy}
        }
        handle {
          ${mkForwardAuthBlock}
          ${proxy}
        }
      ''
    else if hasForwardAuth then
      ''
        ${mkForwardAuthBlock}
        ${proxy}
      ''
    else
      ''
        ${proxy}
      '';

  # Auth-freier Body: nur Proxy, kein forward_auth.
  mkProxyOnly = svc: "reverse_proxy http://127.0.0.1:${toString svc.port}";

  # .local = vertraute LAN-Zone. Bei localBypass laeuft L1 OHNE forward_auth,
  # damit "dumme" Geraete (Fire TV, Smart-TV, Sonos ...) ohne SSO drankommen.
  # Kein Sicherheitsloch: .local ist Multicast-LAN-only, verlaesst das Netz nie,
  # und die Dienste binden weiterhin ausschliesslich auf 127.0.0.1.
  localBypass = cfg.ingress.auth.localBypass;
  mkLocalBody = svc: if localBypass then mkProxyOnly svc else mkProxyBody svc;

  # Standalone: ein Matcher fuer alle Hosts des Dienstes (L1 + optional L2).
  # Nur zulaessig wenn L1 und L2 dieselbe Auth-Policy haben.
  mkSvcBlock =
    name: svc:
    ''
      @${name} host ${hostList name}
      handle @${name} {
        ${mkProxyBody svc}
      }
    '';

  # Immer Routen erzeugen (auch ohne Domain -- dann nur .local).
  mkSvcRoutes = lib.concatStringsSep "\n" (lib.mapAttrsToList mkSvcBlock enabledServices);

  # Nur L1-Routen (fuer :80 bei tls=custom -- Domain geht auf :443).
  mkLocalOnlyBlock =
    name: svc:
    ''
      @${name}_local host ${name}.local
      handle @${name}_local {
        ${mkLocalBody svc}
      }
    '';
  mkLocalOnlyRoutes = lib.concatStringsSep "\n" (
    lib.mapAttrsToList mkLocalOnlyBlock enabledServices
  );

  # Wenn .local auth-frei ist, aber die Domain forward_auth nutzt, duerfen L1/L2
  # nicht mehr im selben Matcher liegen -- dann getrennte Bloecke erzeugen.
  splitAuth = localBypass && hasForwardAuth;
  mkAllRoutes =
    if splitAuth then
      lib.concatStringsSep "\n" [
        mkLocalOnlyRoutes
        mkDomainOnlyRoutes
      ]
    else
      mkSvcRoutes;

  # Nur L2-Routen (Domain).
  mkDomainOnlyBlock =
    name: svc:
    ''
      @${name}_dom host ${name}.${domain}
      handle @${name}_dom {
        ${mkProxyBody svc}
      }
    '';
  mkDomainOnlyRoutes = lib.optionalString hasDomain (
    lib.concatStringsSep "\n" (lib.mapAttrsToList mkDomainOnlyBlock enabledServices)
  );

  domainHostList = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: _: "${name}.${domain}") enabledServices
  );

  tlsDirective =
    if tlsMode == "internal" then
      "tls internal"
    else if tlsMode == "custom" then
      "tls ${cfg.ingress.tls.certFile} ${cfg.ingress.tls.keyFile}"
    else
      "";

  # TLS-Policy (Phase B):
  #   off:      alles auf :80 (L1 + L2)
  #   internal: :80 -> https redir; :443 mit tls internal fuer L1+L2
  #   custom:   L1 bleibt HTTP auf :80 (LE-Cert matcht .local nicht);
  #             L2 :80 -> redir, L2 auf :443 mit custom cert
  standaloneConfig = pkgs.writeText "Caddyfile-media-standalone" (
    if !tlsOn then
      ''
        :80 {
          route /health {
            respond "OK" 200
          }
          ${mkAllRoutes}
        }
      ''
    else if tlsMode == "internal" then
      ''
        :80 {
          redir https://{host}{uri} 308
        }
        :443 {
          ${tlsDirective}
          route /health {
            respond "OK" 200
          }
          ${mkAllRoutes}
        }
      ''
    else
      # custom
      ''
        :80 {
          route /health {
            respond "OK" 200
          }
          ${mkLocalOnlyRoutes}
          ${lib.optionalString hasDomain ''
            @domainHosts host ${domainHostList}
            handle @domainHosts {
              redir https://{host}{uri} 308
            }
          ''}
        }
        ${lib.optionalString hasDomain ''
          :443 {
            ${tlsDirective}
            route /health {
              respond "OK" 200
            }
            ${mkDomainOnlyRoutes}
          }
        ''}
      ''
  );

  mkGlobalExtraConfig = svc: mkProxyBody svc;

  # P1-7: pro Service .local-vHost (HTTP-only, kein ACME) + optional Domain-vHost.
  globalLocalVhosts = lib.mapAttrs' (
    name: svc:
    lib.nameValuePair "http://${name}.local" {
      extraConfig = mkLocalBody svc;
    }
  ) enabledServices;

  globalDomainVhosts = lib.optionalAttrs hasDomain (
    lib.mapAttrs' (
      name: svc:
      lib.nameValuePair "${name}.${domain}" {
        extraConfig = mkGlobalExtraConfig svc;
      }
    ) enabledServices
  );

in
{
  imports = [
    ./mdns.nix
    ./ddns.nix
  ];

  config = lib.mkIf cfg.enable (lib.mkMerge [

    # --- Assertions: Fallstrick domain endet nicht auf .local ---
    {
      assertions = [
        {
          assertion = !(hasDomain && lib.hasSuffix ".local" domain);
          message = ''
            [50-media] grapefruitMedia.domain endet auf ".local" ("${toString domain}").
            .local ist ausschliesslich mDNS (RFC 6762) und darf nicht als Unicast-Domain
            gesetzt werden. Nutze eine echte Domain (z.B. media.example.com) oder domain = null.
          '';
        }
      ];
    }

    # --- Standalone-Modus ---
    (lib.mkIf isStandalone {
      systemd.services.caddy-media = {
        description = "Standalone Caddy Ingress for Media Stack (${tlsMode})";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          # P1-6: Caddyfile-Adapter explizit.
          ExecStart = "${pkgs.caddy}/bin/caddy run --adapter caddyfile --config ${standaloneConfig}";

          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

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
      users.groups.caddy-media = { };
    })

    # --- Global-Modus: L1 immer + L2 bei Domain (P0-3 / P1-7) ---
    (lib.mkIf isGlobal {
      services.caddy.virtualHosts = globalLocalVhosts // globalDomainVhosts;
    })

    # --- Auth / TLS Warnings ---
    {
      warnings =
        lib.optional
          (
            cfg.enable
            && cfg.ingress.enable
            && cfg.ingress.auth.mode == "forward-auth"
            && !cfg.authProxyPresent
          )
          ''
            [50-media/ingress] ingress.auth.mode = "forward-auth" aber
            grapefruitMedia.authProxyPresent = false. Setze authProxyPresent = true
            damit *arr-Apps ebenfalls AUTH__METHOD=External verwenden.
          ''
        ++ lib.optional
          (
            cfg.enable
            && cfg.ingress.enable
            && cfg.ingress.auth.mode == "forward-auth"
            && cfg.ingress.auth.forwardAuthUpstream == ""
          )
          ''
            [50-media/ingress] auth.mode = "forward-auth" erfordert
            grapefruitMedia.ingress.auth.forwardAuthUpstream
            (z.B. http://127.0.0.1:4180).
          ''
        ++ lib.optional
          (
            cfg.enable
            && cfg.ingress.enable
            && cfg.ingress.tls.mode == "custom"
            && (cfg.ingress.tls.certFile == null || cfg.ingress.tls.keyFile == null)
          )
          ''
            [50-media/ingress] tls.mode = "custom" erfordert
            grapefruitMedia.ingress.tls.certFile und .keyFile.
          ''
        ++ lib.optional
          (
            cfg.enable
            && cfg.ingress.enable
            && isStandalone
            && tlsMode == "custom"
            && !hasDomain
          )
          ''
            [50-media/ingress] tls.mode = "custom" ohne domain: L2/HTTPS-Domain-vHosts
            entfallen; nur {service}.local auf :80 (HTTP). Fuer HTTPS eine Domain setzen.
          '';
    }

    # --- DNS-Kanon (Phase B live) ---
    # L1 mDNS  {service}.local  = discovery.mdns (./mdns.nix) + Caddy host matcher
    # L2       {service}.{domain} = nur hasDomain; nie domain=*.local (assertion)
    # Tiers/CF: lib/service-tiers.nix + README (3-Anker) -- Export Phase C
  ]);
}
