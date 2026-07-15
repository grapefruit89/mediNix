{ config, lib, pkgs, ... }:

with lib;

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
    enable = mkEnableOption "Standalone Media Stack Module";

    domain = mkOption {
      type = types.str;
      default = "grapefruit-media.local";
      description = "Base domain used for local ingress routing (e.g. *.grapefruit-media.local).";
    };

    # Service enable options
    jellyfin.enable = mkEnableOption "Jellyfin Media Server";
    jellyseerr.enable = mkEnableOption "Jellyseerr Request Manager";
    sonarr.enable = mkEnableOption "Sonarr TV Series Manager";
    radarr.enable = mkEnableOption "Radarr Movies Manager";
    readarr.enable = mkEnableOption "Readarr Books Manager";
    prowlarr.enable = mkEnableOption "Prowlarr Indexer Proxy";
    sabnzbd.enable = mkEnableOption "SABnzbd Usenet Downloader";
    audiobookshelf = {
      enable = mkEnableOption "Audiobookshelf Server";
      enableQuickSync = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Intel QSV GPU transcode mapping.";
      };
    };
    navidrome.enable = mkEnableOption "Navidrome Music Server";
    lidarr.enable = mkEnableOption "Lidarr Music Download Manager";
    recyclarr = {
      enable = mkEnableOption "Recyclarr custom format synchronization";
      schedule = mkOption {
        type = types.str;
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
      enable = mkEnableOption "Prometheus exporters for Arr stack";
      lidarr.enable = mkEnableOption "Enable metrics exporter for Lidarr";
    };
    usenet-confinement.enable = mkEnableOption "Run Usenet stack (SABnzbd/Prowlarr) isolated under WireGuard VPN interface";

    authProxyPresent = mkOption {
      type = types.bool;
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
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Caddy ingress mapping (reverse proxying subdomains).";
      };
      mode = mkOption {
        type = types.enum [ "auto" "global" "standalone" ];
        default = "auto";
        description = ''
          auto: Hook into global caddy if config.services.caddy.enable is true, fallback to standalone caddy-media if false.
          global: Force injection into global Caddy.
          standalone: Force standalone caddy-media systemd service on port 80/443.
        '';
      };
      tls = {
        mode = mkOption {
          type = types.enum [ "off" "internal" "custom" ];
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
        certFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "/var/lib/acme/example.com/cert.pem";
          description = "Pfad zum TLS-Zertifikat (PEM, Chain). Nur bei tls.mode = custom.";
        };
        keyFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "/var/lib/acme/example.com/key.pem";
          description = "Pfad zum TLS-Private-Key (PEM). Nur bei tls.mode = custom.";
        };
      };
      auth = {
        mode = mkOption {
          type = types.enum [ "none" "forward-auth" ];
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
        forwardAuthUrl = mkOption {
          type = types.str;
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
        skipPaths = mkOption {
          type = types.listOf types.str;
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
      jellyfin = mkOption { type = types.port; default = 5001; };
      jellyseerr = mkOption { type = types.port; default = 5002; };
      sonarr = mkOption { type = types.port; default = 5003; };
      radarr = mkOption { type = types.port; default = 5004; };
      readarr = mkOption { type = types.port; default = 5005; };
      prowlarr = mkOption { type = types.port; default = 5006; };
      sabnzbd = mkOption { type = types.port; default = 5007; };
      audiobookshelf = mkOption { type = types.port; default = 5008; };
      navidrome = mkOption { type = types.port; default = 5009; };
      lidarr = mkOption { type = types.port; default = 5010; };
      exportarr-sonarr = mkOption { type = types.port; default = 4070; };
      exportarr-radarr = mkOption { type = types.port; default = 4071; };
      exportarr-prowlarr = mkOption { type = types.port; default = 4072; };
      exportarr-lidarr = mkOption { type = types.port; default = 4073; };
    };

    # System Configuration Defaults
    hardware = {
      ramGB = mkOption {
        type = types.int;
        default = 16;
        description = "Total host RAM in GB, used to scale adaptive transcode memory rules.";
      };
      renderDevice = mkOption {
        type = types.str;
        default = "/dev/dri/renderD128";
        description = "Path to host GPU render device for QuickSync ffmpeg transcode.";
      };
    };

    locale = {
      language = mkOption { type = types.str; default = "en"; };
      default = mkOption { type = types.str; default = "en_US.UTF-8"; };
    };

    storage = {
      enable = mkOption { type = types.bool; default = true; };
      mediaRoot = mkOption {
        type = types.path;
        default = "/data";
        description = "Base directory for media storage downloads/library.";
      };
      metadataDir = mkOption {
        type = types.path;
        default = "/var/lib/media-metadata";
        description = "Base directory for heavy metadata artwork stores.";
      };
    };

    onDemand = {
      enable = mkOption { type = types.bool; default = false; };
      internalOffset = mkOption { type = types.int; default = 1000; };
      idleTimeoutSec = mkOption { type = types.int; default = 900; };
    };

    vpn = {
      interface = mkOption {
        type = types.str;
        default = "privado";
        description = "Interface name of the WireGuard sandbox interface.";
      };
      dns = mkOption {
        type = types.listOf types.str;
        default = [ "1.1.1.1" "1.0.0.1" ];
        description = "DNS servers to configure for sandbox isolation.";
      };
    };

    # External Secrets Configuration Interface (R4 / sops-nix bridge)
    secrets = {
      secretsDir = mkOption {
        type = types.str;
        default = "/var/lib/media-secrets";
        description = "Base path for all internal and generated secrets.";
      };
      arrApiKeyFile = mkOption {
        type = types.str;
        default = "${cfg.secrets.secretsDir}/arr-apikey";
        description = "Path where the autogenerated Arr shared API key is saved (fallback when no per-service key is set).";
      };

      # Per-Service-API-Keys (K4-Fix). Defaults auf arrApiKeyFile fuer Rueckwaertskompatibilitaet.
      # compat-my.nix mappt diese auf /var/lib/secrets/<svc>_api_key (media-secrets.nix).
      sonarrApiKeyFile = mkOption {
        type = types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Sonarr API key file (per-service, see K4 in claude-review.md).";
      };
      radarrApiKeyFile = mkOption {
        type = types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Radarr API key file.";
      };
      prowlarrApiKeyFile = mkOption {
        type = types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Prowlarr API key file.";
      };
      lidarrApiKeyFile = mkOption {
        type = types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Lidarr API key file.";
      };
      readarrApiKeyFile = mkOption {
        type = types.str;
        default = cfg.secrets.arrApiKeyFile;
        description = "Path to Readarr API key file.";
      };
      navidromeOidcFile = mkOption {
        type = types.path;
        default = "${cfg.secrets.secretsDir}/navidrome-oidc.env";
        description = "Path to Navidrome Client OIDC configuration.";
      };
      jellyseerrEnvFile = mkOption {
        type = types.path;
        default = "${cfg.secrets.secretsDir}/jellyseerr.env";
        description = "Path to Jellyseerr API configuration environment file.";
      };
      autoGenerate = mkOption {
        type = types.bool;
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
      enable = mkEnableOption "Hook state paths into local impermanence bindings";
      extraPaths = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Override or add paths to persist outside root ramfs.";
      };
    };
  };

  # Review K3 (claude-review.md): Der fruehere allowedTCPPorts-Block (13 Ports
  # pauschal offen) wurde entfernt. Dienste binden an 127.0.0.1 und werden
  # ausschliesslich ueber den Ingress exponiert. LAN-Exposition muss ein
  # Konsument explizit selbst konfigurieren.

  config = mkIf cfg.enable {
    # M9-Fix: users.groups.media zentral definiert statt in 4 einzelnen Service-Dateien
    # (510, 520, 530, 540 setzen alle media = {}; Merge-Semantik macht das sicher,
    # aber eine zentrale Definition ist klarer).
    users.groups.media = {};
  };
}
