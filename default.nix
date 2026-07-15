{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.grapefruitMedia;
in {
  imports = [
    ./500-media-ingress
    ./500-media-ingress/on-demand.nix
    ./510-jellyfin
    ./520-arr-stack
    ./520-arr-stack/secrets-generator.nix
    ./530-sabnzbd
    ./540-audiobookshelf
    ./550-navidrome
    ./560-recyclarr
    ./570-exportarr
    ./580-libreseerr
    ./590-usenet-confinement
    ./591-secrets-portal
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
    libreseerr.enable = mkEnableOption "Libreseerr OCI container service";
    recyclarr = {
      enable = mkEnableOption "Recyclarr custom format synchronization";
      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Systemd calendar interval for Recyclarr runs.";
      };
    };
    exporters = {
      enable = mkEnableOption "Prometheus exporters for Arr stack";
      lidarr.enable = mkEnableOption "Enable metrics exporter for Lidarr";
    };
    usenet-confinement.enable = mkEnableOption "Run Usenet stack (SABnzbd/Prowlarr) isolated under WireGuard VPN interface";

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
        type = types.path;
        default = "${cfg.secrets.secretsDir}/arr-apikey";
        description = "Path where the autogenerated Arr shared API key is saved.";
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

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkDefault [
      cfg.ports.jellyfin
      cfg.ports.jellyseerr
      cfg.ports.sonarr
      cfg.ports.radarr
      cfg.ports.readarr
      cfg.ports.prowlarr
      cfg.ports.sabnzbd
      cfg.ports.audiobookshelf
      cfg.ports.navidrome
      cfg.ports.lidarr
      cfg.ports.libreseerr
      cfg.ports.secrets-portal
    ];
  };
}
