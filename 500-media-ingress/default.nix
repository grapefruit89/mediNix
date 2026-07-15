# ---
# id: "media-ingress"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Chamaelon-Ingress -- standalone caddy-media oder global Caddy vHosts fuer alle Dienste"
# provides: [caddy-media (standalone), services.caddy.virtualHosts (global)]
# requires: [grapefruitMedia.ingress, grapefruitMedia.domain]
# tags: [caddy, ingress, reverse-proxy]
# docs:
#   - modules/50-media/claude-review.md
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  domain = cfg.domain;
  ports = cfg.ports;

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

  # H6-Fix: alle aktivierten Dienste mit ihren Ports -- fuer globalen und
  # Standalone-Modus gemeinsam genutzt.
  enabledServices = lib.filterAttrs (_: v: v != null) {
    jellyfin = lib.optionalAttrs cfg.jellyfin.enable { port = ports.jellyfin; };
    jellyseerr = lib.optionalAttrs cfg.jellyseerr.enable { port = ports.jellyseerr; };
    sonarr = lib.optionalAttrs cfg.sonarr.enable { port = ports.sonarr; };
    radarr = lib.optionalAttrs cfg.radarr.enable { port = ports.radarr; };
    readarr = lib.optionalAttrs cfg.readarr.enable { port = ports.readarr; };
    prowlarr = lib.optionalAttrs cfg.prowlarr.enable { port = ports.prowlarr; };
    sabnzbd = lib.optionalAttrs cfg.sabnzbd.enable { port = ports.sabnzbd; };
    audiobookshelf = lib.optionalAttrs cfg.audiobookshelf.enable { port = ports.audiobookshelf; };
    navidrome = lib.optionalAttrs cfg.navidrome.enable { port = ports.navidrome; };
    lidarr = lib.optionalAttrs cfg.lidarr.enable { port = ports.lidarr; };
  };

  # Caddyfile-Snippet: pro Dienst Matcher + (optionaler forward_auth) + reverse_proxy
  mkSvcRoutes = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: svc:
      ''
        @${name} host ${name}.${domain}
        handle @${name} {
          ${forwardAuthSnippet}reverse_proxy http://127.0.0.1:${toString svc.port}
        }
      ''
    ) enabledServices
  );

  # TLS-Direktive fuer den Standalone-Block
  tlsDirective =
    if cfg.ingress.tls.mode == "internal" then
      "tls internal"
    else if cfg.ingress.tls.mode == "custom" then
      # Zertifikat kommt von security.acme/lego (ADR-032), nicht von Caddy-ACME
      "tls ${cfg.ingress.tls.certFile} ${cfg.ingress.tls.keyFile}"
    else
      "";  # off = kein TLS-Snippet

  standaloneProtocol = if cfg.ingress.tls.mode != "off" then "https" else "http";

  # forward_auth Snippet (leer bei auth.mode = "none")
  forwardAuthSnippet = lib.optionalString (cfg.ingress.auth.mode == "forward-auth") ''
    forward_auth ${cfg.ingress.auth.forwardAuthUrl}
  '';

  # Matcher fuer Pfade die forward_auth umgehen (skipPaths)
  skipPathsMatcher = lib.optionalString
    (cfg.ingress.auth.mode == "forward-auth" && cfg.ingress.auth.skipPaths != [ ])
    (let
      paths = lib.concatStringsSep " " cfg.ingress.auth.skipPaths;
    in "@noAuth path ${paths}");

  # Caddyfile fuer Standalone-Modus
  # H6-Fix: Site-Adresse :80 (catch-all) statt "http://localhost:80" (nur localhost-Header)
  standaloneConfig = pkgs.writeText "Caddyfile-media-standalone" ''
    :80 {
      route /health {
        respond "OK" 200
      }
      ${mkSvcRoutes}
    }
    ${lib.optionalString (cfg.ingress.tls.mode == "internal") ''
      :443 {
        ${tlsDirective}
        ${mkSvcRoutes}
      }
    ''}
  '';
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [

    # --- Standalone-Modus ---
    (lib.mkIf isStandalone {
      systemd.services.caddy-media = {
        description = "Standalone Caddy Ingress for Media Stack (${cfg.ingress.tls.mode})";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.caddy}/bin/caddy run --config ${standaloneConfig}";

          # CAP_NET_BIND_SERVICE fuer Port 80/443
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

    # --- Global-Modus: vHosts fuer ALLE aktivierten Dienste ---
    # H6-Fix: nicht mehr hardkodierte 3 Dienste, sondern map ueber enabledServices
    (lib.mkIf isGlobal {
      services.caddy.virtualHosts = lib.mapAttrs' (
        name: svc:
        lib.nameValuePair "${name}.${domain}" {
          extraConfig = ''
            ${forwardAuthSnippet}reverse_proxy http://127.0.0.1:${toString svc.port}
          '';
        }
      ) enabledServices;
    })

    # --- Phase 3.2: Auth-Warnings + Assertions ---
    {
      warnings =
        # Warnung: auth.mode=forward-auth aber authProxyPresent nicht gesetzt
        lib.optional
          (cfg.enable && cfg.ingress.enable
            && cfg.ingress.auth.mode == "forward-auth"
            && !cfg.authProxyPresent)
          ''
            [50-media/ingress] ingress.auth.mode = "forward-auth" aber
            grapefruitMedia.authProxyPresent = false. Setze authProxyPresent = true
            damit *arr-Apps ebenfalls AUTH__METHOD=External verwenden.
          ''
        # Warnung: auth.mode=forward-auth aber forwardAuthUrl leer
        ++ lib.optional
          (cfg.enable && cfg.ingress.enable
            && cfg.ingress.auth.mode == "forward-auth"
            && cfg.ingress.auth.forwardAuthUrl == "")
          ''
            [50-media/ingress] auth.mode = "forward-auth" erfordert
            grapefruitMedia.ingress.auth.forwardAuthUrl (z.B. http://127.0.0.1:4180/oauth2/auth).
          ''
        # Warnung: custom TLS aber certFile oder keyFile fehlt
        ++ lib.optional
          (cfg.enable && cfg.ingress.enable
            && cfg.ingress.tls.mode == "custom"
            && (cfg.ingress.tls.certFile == null || cfg.ingress.tls.keyFile == null))
          ''
            [50-media/ingress] tls.mode = "custom" erfordert
            grapefruitMedia.ingress.tls.certFile und .keyFile.
          '';
    }

    # --- DNS-Empfehlung (Block 7, 2026-07-15) ---
    # KEIN .local (mDNS-Konflikt RFC 6762). Empfohlenes Setup:
    #   grapefruitMedia.domain = "grapefruit-media.home.arpa"   # RFC 8375 Short-Names
    #   Oder: kanonische Domain (z.B. example.com) mit Split-Horizon:
    #     - Intern:   Blocky-Rewrite *.example.com -> LAN-IP
    #     - Extern:   Cloudflare DDNS
    #     - TLS:      lego DNS-01 Wildcard-Cert via security.acme (ADR-032)
    # Diese Datei ist darauf vorbereitet: domain-Option parametrisiert alle vHosts.
    # Keine .local-Defaults in dieser Datei.
  ]);
}
