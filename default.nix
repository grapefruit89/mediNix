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
    # 551-feishin: OCI-Container entfernt (POL-FT-001 Docker verboten, Review K6).
    #   Feishin ist eine SPA -- nativer Caddy file_server waere policy-konform.
    #   feishin.enable Option bleibt deklariert (kein Bruch fuer bestehende Config).
    # 580-libreseerr: OCI-Container entfernt (Review K6). Natives Modul:
    #   modules/60-apps/62-libreseerr.nix (laeuft via rollout Stufe 7).
    # 591-secrets-portal: Python-Inline-Prototyp entfernt (Review K5).
    #   Natives Go-Modul: modules/20-security/2029-secrets-portal.nix.
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
    feishin = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Feishin Music Client (Web UI). OCI-Container-Implementierung entfernt
          (Review K6: POL-FT-001 Docker verboten). Natives statisches Frontend
          (Caddy file_server) noch nicht implementiert. Option bleibt deklariert,
          hat aber keinen Effekt bis eine native Implementierung existiert.
        '';
      };
    };
    libreseerr = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Libreseerr (OCI-Container-Variante entfernt -- Review K6).
          Natives Modul: modules/60-apps/62-libreseerr.nix.
          Diese Option hat keinen Effekt mehr.
        '';
      };
    };
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
          type = types.enum [ "off" "internal" "acme" ];
          default = "off";
          description = ''
            TLS-Modus fuer den Standalone-Ingress:
              off:      nur HTTP auf :80 (kein TLS -- fuer LAN hinter eigenem Proxy).
              internal: HTTP :80 + HTTPS :443 mit Caddy-interner CA (selbstsigniert,
                        Browser zeigt Warnung). Fuer lokale Entwicklung geeignet.
              acme:     NICHT im Modul verwenden (ADR-032: TLS gehoert auf Host-Ebene
                        via security.acme/lego + DNS-01). Diese Option ist ein
                        Reminder-Platzhalter und hat keine Auswirkung.
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
      feishin = mkOption { type = types.port; default = 5012; };
      libreseerr = mkOption { type = types.port; default = 6010; };
      secrets-portal = mkOption { type = types.port; default = 5011; };
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
      usenetFile = mkOption {
        type = types.path;
        default = "${cfg.secrets.secretsDir}/usenet.env";
        description = "Path to Usenet provider credential file (configured via Portal or SOPS).";
      };
      vpnFile = mkOption {
        type = types.path;
        default = "${cfg.secrets.secretsDir}/vpn.env";
        description = "Path to WireGuard/VPN credential files.";
      };
      indexersFile = mkOption {
        type = types.path;
        default = "${cfg.secrets.secretsDir}/indexers.env";
        description = "Path to indexer API keys/settings.";
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
      portal.enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Python-Inline-Prototyp (591-secrets-portal) entfernt (Review K5:
          unauthentifiziert, Permissions-Deadlock, ExecStart nicht parsebar).
          Natives Go-Modul: modules/20-security/2029-secrets-portal.nix
          (my.services.secrets-portal.enable). Diese Option hat keinen Effekt.
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
