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
#   - modules/50-media/README.md
# ---
# Bugfixes Phase 3 Nacharbeit (2026-07-15):
#   Bug1: enabledServices-Filter (optionalAttrs false == {}, nicht null) -- gefixt
#   Bug2: forward_auth Upstream enthielt Pfad (Caddy: uri als Subdirektive) -- gefixt
#   Bug3: skipPaths war No-Op (Matcher definiert aber nie verdrahtet) -- gefixt
#   Bug4: tls.mode=custom hatte keinen :443-Block, :80 ohne Redirect -- gefixt
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
  domain = cfg.domain;
  # P0-1/P0-3(L2-Teil): L2-vHosts nur wenn eine echte Domain gesetzt ist.
  # Ohne Domain bleibt der Ingress leer -- die {service}.local-Matcher kommen
  # mit der mDNS-Arbeit in Phase B (P1-1 + P0-3 vollstaendig) dazu.
  hasDomain = domain != null && domain != "";
  ports = cfg.ports;
  auth = cfg.ingress.auth;

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

  # Bug1 Fix: lib.optionalAttrs false ergibt {} (leeres Attrset), nicht null --
  # filterAttrs (_: v: v != null) filterte deshalb nie. Gefixt: if/else null.
  enabledServices = lib.filterAttrs (_: v: v != null) {
    jellyfin       = if cfg.jellyfin.enable       then { port = ports.jellyfin; }       else null;
    jellyseerr     = if cfg.jellyseerr.enable     then { port = ports.jellyseerr; }     else null;
    sonarr         = if cfg.sonarr.enable         then { port = ports.sonarr; }         else null;
    radarr         = if cfg.radarr.enable         then { port = ports.radarr; }         else null;
    readarr        = if cfg.readarr.enable        then { port = ports.readarr; }        else null;
    prowlarr       = if cfg.prowlarr.enable       then { port = ports.prowlarr; }       else null;
    sabnzbd        = if cfg.sabnzbd.enable        then { port = ports.sabnzbd; }        else null;
    audiobookshelf = if cfg.audiobookshelf.enable then { port = ports.audiobookshelf; } else null;
    navidrome      = if cfg.navidrome.enable      then { port = ports.navidrome; }      else null;
    lidarr         = if cfg.lidarr.enable         then { port = ports.lidarr; }         else null;
  };

  hasForwardAuth = auth.mode == "forward-auth";
  hasSkipPaths   = hasForwardAuth && auth.skipPaths != [ ];
  skipPathsStr   = lib.concatStringsSep " " auth.skipPaths;

  # Bug2 Fix: Caddy forward_auth-Syntax: <upstream> ohne Pfad + uri als Subdirektive.
  # Kontext7 bestaetigt: forward_auth <upstream> { uri <pfad>; copy_headers ...; }
  # forwardAuthUrl aufgeteilt in forwardAuthUpstream + forwardAuthUri (default /oauth2/auth).
  mkForwardAuthBlock = ''
    forward_auth ${auth.forwardAuthUpstream} {
      uri ${auth.forwardAuthUri}
      copy_headers Remote-User Remote-Email Remote-Groups X-Auth-Request-User X-Auth-Request-Email
    }
  '';

  # Bug3 Fix: skipPaths jetzt verdrahtet. Zwei handle-Bloecke: @<name>Skip geht direkt
  # zur reverse_proxy, alles andere wird erst durch forward_auth geschleust.
  mkSvcBlock =
    name: svc:
    let
      proxy = "reverse_proxy http://127.0.0.1:${toString svc.port}";
    in
    ''
      @${name} host ${name}.${domain}
      handle @${name} {
        ${
          if hasSkipPaths then
            ''
              @${name}Skip path ${skipPathsStr}
              handle @${name}Skip {
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
            ''
        }
      }
    '';

  # Ohne gesetzte Domain (nur mDNS-Zukunft): keine L2-Routen erzeugen.
  mkSvcRoutes =
    if hasDomain then
      lib.concatStringsSep "\n" (lib.mapAttrsToList mkSvcBlock enabledServices)
    else
      "";

  # TLS-Direktive fuer den Standalone-Block
  tlsDirective =
    if cfg.ingress.tls.mode == "internal" then
      "tls internal"
    else if cfg.ingress.tls.mode == "custom" then
      # Zertifikat kommt von security.acme/lego (ADR-032), nicht von Caddy-ACME
      "tls ${cfg.ingress.tls.certFile} ${cfg.ingress.tls.keyFile}"
    else
      "";

  # Bug4 Fix: tls.mode=custom bekommt jetzt :443-Block (wie internal).
  # Bei aktivem TLS leitet :80 auf :443 um (308 Permanent Redirect).
  # standaloneProtocol entfernt (war totes Code).
  standaloneConfig = pkgs.writeText "Caddyfile-media-standalone" (
    if cfg.ingress.tls.mode == "off" then
      ''
        :80 {
          route /health {
            respond "OK" 200
          }
          ${mkSvcRoutes}
        }
      ''
    else
      ''
        :80 {
          redir https://{host}{uri} 308
        }
        :443 {
          ${tlsDirective}
          route /health {
            respond "OK" 200
          }
          ${mkSvcRoutes}
        }
      ''
  );

  # Globaler vHost extraConfig (Bug2+3 Fix: korrekte forward_auth + skipPaths)
  mkGlobalExtraConfig =
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
          # P1-6: Caddyfile-Adapter explizit -- ohne --adapter caddyfile erwartet
          # `caddy run --config` je nach Version JSON und scheitert am Caddyfile.
          ExecStart = "${pkgs.caddy}/bin/caddy run --adapter caddyfile --config ${standaloneConfig}";

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
    # Nur bei gesetzter Domain -- ohne Domain gibt es (noch) keine L2-vHosts.
    (lib.mkIf (isGlobal && hasDomain) {
      services.caddy.virtualHosts = lib.mapAttrs' (
        name: svc:
        lib.nameValuePair "${name}.${domain}" {
          extraConfig = mkGlobalExtraConfig svc;
        }
      ) enabledServices;
    })

    # --- Phase 3.2: Auth-Warnings ---
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
          '';
    }

    # --- DNS-Kanon: grok-review.md (SSoT), Stand 2026-07-15 ---
    # L1 mDNS  {service}.local  = immer (Avahi, Phase B) -- nie in Cloudflare.
    # L2       {service}.{domain} = nur wenn cfg.domain gesetzt (hasDomain).
    #          domain NIE auf .local enden lassen -- echte Domain fuer Unicast.
    # Tiers/CF-Anker: siehe lib/service-tiers.nix + README (3-Routen-Modell).
    # Diese Datei erzeugt L2-vHosts nur bei gesetzter Domain; der .local-Matcher
    # kommt mit P1-1 (mDNS) + P0-3 (Doppel-Matcher) in Phase B dazu.
  ]);
}
