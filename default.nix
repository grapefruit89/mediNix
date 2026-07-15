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
in {
  imports = [
    ./500-media-ingress
    ./520-arr-stack/on-demand.nix
    ./510-jellyfin
    ./520-arr-stack
    ./520-arr-stack/secrets-generator.nix
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
      type = lib.types.str;
      default = "grapefruit-media.local";
      description = "Base domain used for local ingress routing (e.g. *.grapefruit-media.local).";
    };

    # Service enable options
    jellyfin.enable = lib.mkEnableOption "Jellyfin Media Server";
    jellyseerr.enable = lib.mkEnableOption "Jellyseerr Request Manager";
    sonarr.enable = lib.mkEnableOption "Sonarr TV Series Manager";
    radarr.enable = lib.mkEnableOption "Radarr Movies Manager";
    readarr.enable = lib.mkEnableOption "Readarr Books Manager";
    prowlarr.enable = lib.mkEnableOption "Prowlarr Indexer Proxy";
    sabnzbd.enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
    audiobookshelf = {
      enable = lib.mkEnableOption "Audiobookshelf Server";
      enableQuickSync = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Intel QSV GPU transcode mapping.";
      };
    };
    navidrome.enable = lib.mkEnableOption "Navidrome Music Server";
    lidarr.enable = lib.mkEnableOption "Lidarr Music Download Manager";
    recyclarr = {
      enable = lib.mkEnableOption "Recyclarr custom format synchronization";
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
              forward-auth: Jede Anfrage wird gegen forwardAuthUrl geprueft
                            (z.B. oauth2-proxy, Pocket-ID, Authentik).
                            Setze zusaetzlich grapefruitMedia.authProxyPresent = true,
                            damit *arr-Apps ebenfalls AUTH__METHOD=External erhalten.
          '';
        };
        forwardAuthUrl = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "http://127.0.0.1:4180/oauth2/auth";
          description = ''
            Vollstaendige URL des Forward-Auth-Endpoints.
            Nur relevant bei auth.mode = forward-auth.
            Beispiele:
              oauth2-proxy:  http://127.0.0.1:4180/oauth2/auth
              Pocket-ID:     http://127.0.0.1:8080/api/v1/auth
              Authentik:     http://127.0.0.1:9000/outpost.goauthentik.io/auth/caddy
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

    vpn = {
      interface = lib.mkOption {
        type = lib.types.str;
        default = "privado";
        description = "Interface name of the WireGuard sandbox interface.";
      };
      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "1.1.1.1" "1.0.0.1" ];
        description = "DNS servers to configure for sandbox isolation.";
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
