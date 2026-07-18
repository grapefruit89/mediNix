# ---
# id: "grapefruitMedia"
# domain: "50"
# status: "active"
# layer: 3
# purpose: "Optionen + zentrales Config-Skelett des grapefruitMedia Standalone-Moduls"
# provides: [grapefruitMedia options, users.groups.media]
# requires: []
# tags: [media, options, module-root]
# docs:
#   - modules/50-media/README.md
#   - modules/50-media/claude-review.md
# ---
{ config, lib, pkgs, ... }:
let
  cfg = config.grapefruitMedia;

  # Paket-Override je Dienst. Bewusst nullOr mit Default null statt eines
  # hartkodierten pkgs.<name>: so bleibt der nixpkgs-Default des jeweiligen
  # NixOS-Moduls die Wahrheit (kein Duplizieren von Upstream-Defaults, kein
  # Bruch wenn ein Attributname sich upstream aendert). Nur wenn der Konsument
  # etwas setzt, wird es durchgereicht.
  mkPackageOption =
    svc:
    lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      defaultText = lib.literalExpression "null";
      example = lib.literalExpression "pkgs.${svc}";
      description = ''
        Optionales Paket-Override fuer ${svc}.

        null (Default) = das Paket, das das NixOS-Modul aus nixpkgs vorgibt.
        Setzen, um eine abweichende Version, ein Overlay oder ein Downgrade bei
        einem kaputten Upstream-Release zu verwenden.
      '';
    };
in {
  imports = [
    ./500-media-ingress
    ./520-arr-stack/on-demand.nix
    ./510-jellyfin
    ./520-arr-stack
    ./520-arr-stack/secrets-generator.nix
    ./525-provision
    ./530-sabnzbd
    ./540-audiobookshelf
    ./550-navidrome
    ./560-recyclarr
    ./570-exportarr
    ./590-usenet-confinement
  ];

  options.grapefruitMedia = {
    enable = lib.mkEnableOption "Standalone Media Stack Module";

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "media.example.com";
      description = ''
        Optionale Unicast-Base-Domain fuer die L2-vHosts ({service}.{domain}).

        null (Default) oder "" = KEINE L2-Namen. Die L1-mDNS-Identitaet
        {service}.local laeuft davon unabhaengig immer (Phase B).

        WICHTIG (grok-review.md Fallstrick): NIEMALS auf .local enden lassen --
        .local ist ausschliesslich Multicast-DNS (RFC 6762) und gehoert nie in
        Cloudflare oder einen Unicast-Rewrite. Fuer L2 eine echte Domain setzen
        (z.B. media.example.com), aufgeloest via Cloudflare/Blocky.
      '';
    };

    # Service enable options (+ optionales Paket-Override, siehe mkPackageOption)
    jellyfin = {
      enable = lib.mkEnableOption "Jellyfin Media Server";
      package = mkPackageOption "jellyfin";
    };
    jellyseerr = {
      enable = lib.mkEnableOption "Jellyseerr Request Manager";
      package = mkPackageOption "jellyseerr";
    };
    sonarr = {
      enable = lib.mkEnableOption "Sonarr TV Series Manager";
      package = mkPackageOption "sonarr";
    };
    radarr = {
      enable = lib.mkEnableOption "Radarr Movies Manager";
      package = mkPackageOption "radarr";
    };
    readarr = {
      enable = lib.mkEnableOption "Readarr Books Manager";
      package = mkPackageOption "readarr";
    };
    prowlarr = {
      enable = lib.mkEnableOption "Prowlarr Indexer Proxy";
      package = mkPackageOption "prowlarr";
    };
    sabnzbd = {
      enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
      package = mkPackageOption "sabnzbd";
    };
    audiobookshelf = {
      enable = lib.mkEnableOption "Audiobookshelf Server";
      package = mkPackageOption "audiobookshelf";
      enableQuickSync = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Intel QSV GPU transcode mapping.";
      };
    };
    navidrome = {
      enable = lib.mkEnableOption "Navidrome Music Server";
      package = mkPackageOption "navidrome";
    };
    lidarr = {
      enable = lib.mkEnableOption "Lidarr Music Download Manager";
      package = mkPackageOption "lidarr";
    };
    recyclarr = {
      enable = lib.mkEnableOption "Recyclarr custom format synchronization";
      package = mkPackageOption "recyclarr";
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd calendar interval for Recyclarr runs.";
      };
      # M1-Fix: quality/primaryLanguage/secondaryLanguage entfernt -- waren in
      # 560-recyclarr/default.nix deklariert aber nie ausgewertet (Profile
      # sind hart auf German/English 1080p verdrahtet). Echte Konfiguration
      # erfolgt direkt in 560-recyclarr/default.nix bis ein generisches
      # Template-System implementiert wird.
    };
    exporters = {
      enable = lib.mkEnableOption "Prometheus exporters for Arr stack";
      lidarr.enable = lib.mkEnableOption "Enable metrics exporter for Lidarr";
    };
    usenet-confinement.enable = lib.mkEnableOption "Run Usenet stack (SABnzbd/Prowlarr) isolated under WireGuard VPN interface";

    authProxyPresent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Setze true, wenn ein Forward-Auth-Proxy (z.B. oauth2-proxy, Authentik)
        vor den *arr-Apps aktiv ist und Header-Authentifizierung durchfuehrt.
        Bei true: AUTH__METHOD=External (Proxy authentifiziert).
        Bei false (Standard): AUTH__METHOD=Forms (Nutzer meldet sich direkt an).
        NIEMALS true ohne echten Proxy -- siehe claude-review.md K2.
      '';
    };

    # Chameleon Ingress Options
    ingress = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Caddy ingress mapping (reverse proxying subdomains).";
      };
      mode = lib.mkOption {
        type = lib.types.enum [ "auto" "global" "standalone" ];
        default = "auto";
        description = ''
          auto: Hook into global caddy if config.services.caddy.enable is true, fallback to standalone caddy-media if false.
          global: Force injection into global Caddy.
          standalone: Force standalone caddy-media systemd service on port 80/443.
        '';
      };
      tls = {
        mode = lib.mkOption {
          type = lib.types.enum [ "off" "internal" "custom" ];
          default = "off";
          description = ''
            TLS-Modus fuer den Standalone-Ingress:
              off:      nur HTTP :80 (kein TLS -- fuer LAN hinter eigenem Proxy).
              internal: HTTP :80 + HTTPS :443 mit Caddy-interner CA (selbstsigniert).
                        Gut fuer lokale Entwicklung, Browser zeigt Warnung.
              custom:   HTTPS :443 mit externem Zertifikat (certFile + keyFile).
                        ACME/lego laeuft Host-seitig (ADR-032: security.acme/lego
                        DNS-01), nicht im Modul. Cert-Pfade via tls.certFile/keyFile.
          '';
        };
        certFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/var/lib/acme/example.com/cert.pem";
          description = "Pfad zum TLS-Zertifikat (PEM, Chain). Nur bei tls.mode = custom.";
        };
        keyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/var/lib/acme/example.com/key.pem";
          description = "Pfad zum TLS-Private-Key (PEM). Nur bei tls.mode = custom.";
        };
      };
      auth = {
        mode = lib.mkOption {
          type = lib.types.enum [ "none" "forward-auth" ];
          default = "none";
          description = ''
            Authentifizierungsmodus fuer den Chameleon-Ingress.
              none:         Kein zusaetzlicher Auth-Check (Standard).
              forward-auth: Jede Anfrage wird gegen forwardAuthUpstream geprueft
                            (z.B. oauth2-proxy, Pocket-ID, Authentik).
                            Setze zusaetzlich grapefruitMedia.authProxyPresent = true,
                            damit *arr-Apps ebenfalls AUTH__METHOD=External erhalten.
          '';
        };
        forwardAuthUpstream = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "http://127.0.0.1:4180";
          description = ''
            Upstream-Adresse des Forward-Auth-Proxys (ohne Pfad).
            Nur relevant bei auth.mode = forward-auth.
            Beispiele:
              oauth2-proxy:  http://127.0.0.1:4180
              Pocket-ID:     http://127.0.0.1:8080
              Authentik:     http://127.0.0.1:9000
          '';
        };
        forwardAuthUri = lib.mkOption {
          type = lib.types.str;
          default = "/oauth2/auth";
          description = ''
            Pruef-Pfad auf dem Forward-Auth-Upstream.
            Nur relevant bei auth.mode = forward-auth.
            Beispiele:
              oauth2-proxy:  /oauth2/auth
              Pocket-ID:     /api/v1/auth
              Authentik:     /outpost.goauthentik.io/auth/caddy
          '';
        };
        skipPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/metrics" "/health" "/api/v1/items" ];
          description = ''
            Pfade die forward_auth umgehen (z.B. native App-APIs, Health-Endpoints).
            Gilt global fuer alle vHosts im Ingress.
          '';
        };
        localBypass = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            L1 ({service}.local) ohne forward_auth ausliefern, auch wenn
            auth.mode = "forward-auth" gesetzt ist.

            Warum Default true: .local ist reines Multicast-LAN (RFC 6762) und
            verlaesst das Netz nie -- die physische Netzgrenze ist hier die
            Sicherheitsgrenze. So kommen Geraete ohne SSO-Faehigkeit (Fire TV,
            Smart-TV, Sonos, Konsolen) ohne Passkey-Zwang an die Dienste,
            waehrend {service}.{domain} weiterhin voll authentifiziert bleibt.

            Kein Loch in der Absicherung: die Dienste binden weiterhin nur auf
            127.0.0.1, direkter Zugriff auf IP:Port bleibt tot, und .local ist
            von WAN und WireGuard aus grundsaetzlich nicht erreichbar.

            Auf false setzen, wenn auch im LAN ausnahmslos Auth erzwungen werden soll.
          '';
        };
      };
    };

    # DNS / Namens-Ableitung (Phase C) -- kennt KEINE IPs, keine feste Domain.
    dns = {
      mode = lib.mkOption {
        type = lib.types.enum [ "host" "standalone" ];
        default = "host";
        description = ''
          host (Default): Das Modul liefert nur Tier-Listen und vHost-Namen.
            DDNS, ACME und Cloudflare macht der Host (heutiges q958-Verhalten).
          standalone: Das Modul bringt seinen eigenen DDNS-Sync mit (./ddns.nix).
            Fuer den Drop-in-Betrieb auf fremden Systemen.
        '';
      };

      hostnames = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          navidrome = "music";
          jellyseerr = "seerr";
        };
        description = ''
          Optionaler Override: Servicename -> Hostname-Label. Ohne Eintrag wird der
          Servicename verwendet. Erlaubt die Namenskonvention des Hosts abzubilden
          (z.B. navidrome unter music.{domain}), ohne sie im Modul hart zu kennen.
        '';
      };

      ddns = {
        enable = lib.mkEnableOption "Eigener dynamischer DNS-Sync (nur bei dns.mode = standalone)";

        zone = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "example.com";
          description = "Cloudflare-Zone. null = grapefruitMedia.domain verwenden.";
        };

        interval = lib.mkOption {
          type = lib.types.str;
          default = "5m";
          description = "Pruefintervall des ddclient-Daemons (API-Call nur bei IP-Aenderung).";
        };

        wanJob = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Zusaetzlicher Job, der die edge-wan-Namen auf die oeffentliche IP setzt.
            Default aus: normalerweise macht das der Router per DynDNS. Nur
            einschalten, wenn der Router das nicht kann.
          '';
        };

        tokenCredential = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/var/lib/credstore.encrypted/CF_DDNS_API_TOKEN.cred";
          description = ''
            Pfad zu einem systemd-creds-verschluesselten Cloudflare-API-Token
            (bevorzugt). Wird via LoadCredentialEncrypted geladen.
            Token-Rechte minimal halten: Zone:Read + DNS:Edit, nur diese Zone.
          '';
        };

        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/run/secrets/cloudflare_ddns_token";
          description = ''
            Alternative zu tokenCredential: Klartext-Pfad zur Laufzeit
            (z.B. sops-nix/agenix). Genau eine der beiden Quellen setzen.
          '';
        };
      };
    };

    # Declarative Port Configuration (R4)
    ports = {
      jellyfin = lib.mkOption { type = lib.types.port; default = 5001; };
      jellyseerr = lib.mkOption { type = lib.types.port; default = 5002; };
      sonarr = lib.mkOption { type = lib.types.port; default = 5003; };
      radarr = lib.mkOption { type = lib.types.port; default = 5004; };
      readarr = lib.mkOption { type = lib.types.port; default = 5005; };
      prowlarr = lib.mkOption { type = lib.types.port; default = 5006; };
      sabnzbd = lib.mkOption { type = lib.types.port; default = 5007; };
      audiobookshelf = lib.mkOption { type = lib.types.port; default = 5008; };
      navidrome = lib.mkOption { type = lib.types.port; default = 5009; };
      lidarr = lib.mkOption { type = lib.types.port; default = 5010; };
      exportarr-sonarr = lib.mkOption { type = lib.types.port; default = 4070; };
      exportarr-radarr = lib.mkOption { type = lib.types.port; default = 4071; };
      exportarr-prowlarr = lib.mkOption { type = lib.types.port; default = 4072; };
      exportarr-lidarr = lib.mkOption { type = lib.types.port; default = 4073; };
    };

    # System Configuration Defaults
    hardware = {
      ramGB = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Total host RAM in GB, used to scale adaptive transcode memory rules.";
      };
      renderDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/dri/renderD128";
        description = "Path to host GPU render device for QuickSync ffmpeg transcode.";
      };
    };

    locale = {
      language = lib.mkOption { type = lib.types.str; default = "en"; };
      default = lib.mkOption { type = lib.types.str; default = "en_US.UTF-8"; };
    };

    storage = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };
      mediaRoot = lib.mkOption {
        type = lib.types.path;
        default = "/data";
        description = "Base directory for media storage downloads/library.";
      };
      metadataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/media-metadata";
        description = "Base directory for heavy metadata artwork stores.";
      };
    };

    onDemand = {
      enable = lib.mkOption { type = lib.types.bool; default = false; };
      internalOffset = lib.mkOption { type = lib.types.int; default = 1000; };
      idleTimeoutSec = lib.mkOption { type = lib.types.int; default = 900; };
    };

    # Phase B (P1-1): mDNS L1 -- {service}.local fuer alle UI-Dienste.
    # Nie in Cloudflare (grok-review.md Fallstrick).
    discovery = {
      mdns = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            mDNS/Avahi: publiziert fuer jeden aktivierten UI-Dienst
            {service}.local -> LAN-IP des Hosts (nicht 127.0.0.1).

            Default an. Unabhaengig von grapefruitMedia.domain.
            NIEMALS .local-Namen in Cloudflare oder Unicast-DNS eintragen.
          '';
        };
        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "UDP 5353 (mDNS) in der Firewall oeffnen, wenn Avahi aktiv ist.";
        };
      };
    };

    vpn = {
      interface = lib.mkOption {
        type = lib.types.str;
        default = "privado";
        description = "Interface name of the WireGuard sandbox interface.";
      };
      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "10.8.0.1" ];
        description = ''
          DNS-Server fuer die Usenet-Sandbox. Wird nach /etc/usenet-resolv.conf
          geschrieben und in die confineten Dienste als /etc/resolv.conf gemountet.

          Default ist bewusst LEER: ein stiller Public-DNS-Default (frueher
          1.1.1.1) ist ein Sicherheitsproblem, weil er im Fehlerfall unbemerkt
          greift. Bei aktivem usenet-confinement erzwingt eine Assertion, dass
          hier explizit etwas gesetzt wird.

          WICHTIG -- warum nicht der Host-Resolver: Der Host nutzt systemd-resolved
          mit DoT. Wuerde die Sandbox darueber aufloesen, verliesse die Anfrage den
          Host ueber die normale Uplink-Route und nicht durch den Tunnel -- genau
          der DNS-Leak, den das Confinement verhindern soll.

          Empfohlene Reihenfolge:
            1. DNS des VPN-Providers (liegt im Tunnel, kein Leak zum ISP)
            2. DoT-Resolver, geroutet durch den Tunnel (versteckt die Anfragen
               zusaetzlich vor dem VPN-Provider, braucht einen DoT-Stub)
            3. Public-Resolver im Klartext -- funktioniert, aber der Betreiber
               sieht alle Anfragen
        '';
      };
    };

    # External Secrets Configuration Interface (R4 / sops-nix bridge)
    secrets = {
      secretsDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/media-secrets";
        description = "Base path for all internal and generated secrets.";
      };
      arrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.secrets.secretsDir}/arr-apikey";
        description = "Path where the autogenerated Arr shared API key is saved (fallback when no per-service key is set).";
      };

      # Per-Service-API-Keys (K4-Fix). Defaults auf arrApiKeyFile fuer Rueckwaertskompatibilitaet.
      # compat-my.nix mappt diese auf /var/lib/secrets/<svc>_api_key (media-secrets.nix).
      sonarrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Sonarr API key file (per-service, see K4 in claude-review.md).";
      };
      radarrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Radarr API key file.";
      };
      prowlarrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Prowlarr API key file.";
      };
      lidarrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Lidarr API key file.";
      };
      readarrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Readarr API key file.";
      };
      jellyseerrApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.secrets.secretsDir}/jellyseerr_api_key";
        description = "Pfad zur Jellyseerr-API-Key-Datei (Provisionierung 525).";
      };
      sabnzbdApiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.secrets.secretsDir}/sabnzbd_api_key";
        description = ''
          Pfad zur SABnzbd-API-Key-Datei. Wird von der Provisionierung (525) fuer
          die Download-Client-Registrierung in den *arr benoetigt.
        '';
      };
      jellyfinAdminPasswordFile = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.secrets.secretsDir}/jellyfin_admin_password";
        description = ''
          Pfad zur Datei mit dem Jellyfin-Admin-Passwort. Nur fuer den einmaligen
          Bootstrap durch die Provisionierung (Jellyfin-Setup + Seerr-Init).
        '';
      };
      navidromeOidcFile = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.secrets.secretsDir}/navidrome-oidc.env";
        description = "Path to Navidrome Client OIDC configuration.";
      };
      jellyseerrEnvFile = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.secrets.secretsDir}/jellyseerr.env";
        description = "Path to Jellyseerr API configuration environment file.";
      };
      autoGenerate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Generate a shared Arr API key and per-service env files at boot
          (520-arr-stack/secrets-generator.nix). Default off: overwrites
          existing <service>.env files and uses one shared key for all
          services -- see claude-review.md K4 before enabling.
        '';
      };
    };

    # Impermanence binding hook
    persist = {
      enable = lib.mkEnableOption "Hook state paths into local impermanence bindings";
      extraPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Override or add paths to persist outside root ramfs.";
      };
    };
  };

  # Review K3 (claude-review.md): Der fruehere allowedTCPPorts-Block (13 Ports
  # pauschal offen) wurde entfernt. Dienste binden an 127.0.0.1 und werden
  # ausschliesslich ueber den Ingress exponiert. LAN-Exposition muss ein
  # Konsument explizit selbst konfigurieren.

  config = lib.mkIf cfg.enable {
    # M9-Fix: users.groups.media zentral definiert statt in 4 einzelnen Service-Dateien
    # (510, 520, 530, 540 setzen alle media = {}; Merge-Semantik macht das sicher,
    # aber eine zentrale Definition ist klarer).
    users.groups.media = {};
  };
}
