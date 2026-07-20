# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Kompat-Adapter my.* → grapefruitMedia.* — Eval-Fix nach 50-media-Rewrite (Review K1/H2/H3)
#   docs:
#     - modules/50-media/claude-review.md
#     - docs/adr/011-unified-port-uid-schema.md
#   tags:
#     - media
#     - compat
#     - adapter
# ---
#
# NUR für dieses Repo: mappt den alten my.*-Namespace auf das neue
# Standalone-Modul grapefruitMedia.* und befüllt dessen globale Optionen
# aus den my.*-SSoT-Quellen (Ports, Hardware, Locale, Storage, Secrets,
# VPN, On-Demand, Impermanence).
#
# WICHTIG: Das portable Modul (./default.nix) darf diese Datei NICHT
# importieren — sie referenziert my.configs/my.ports/my.users.registry,
# die auf fremden Systemen nicht existieren. Import erfolgt ausschließlich
# in machines/q958/default.nix.
{
  config,
  lib,
  ...
}:
let
  gm = config.grapefruitMedia;
  uids = config.my.users.registry;
  gids = config.my.groups.registry;

  # Dienste mit 1:1-Alias my.services.<n>.enable → grapefruitMedia.<n>.enable
  simpleServices = [
    "jellyfin"
    "jellyseerr"
    "sonarr"
    "radarr"
    "readarr"
    "prowlarr"
    "sabnzbd"
    "navidrome"
    "lidarr"
  ];

  # *arr + SABnzbd: UID/GID-Pins aus der Registry wie im Altstand (ADR-011).
  # Ohne Pin allokiert isSystemUser dynamisch → Ownership-Drift auf
  # /mnt/fast_pool/metadata und /var/lib/<svc> (Review H2).
  pinnedUsers = [
    "sonarr"
    "radarr"
    "readarr"
    "prowlarr"
    "lidarr"
    "sabnzbd"
  ];

  anyMedia =
    lib.any (n: gm.${n}.enable) simpleServices || gm.audiobookshelf.enable || gm.recyclarr.enable;
in
{
  imports =
    map (
      n: lib.mkAliasOptionModule [ "my" "services" n "enable" ] [ "grapefruitMedia" n "enable" ]
    ) simpleServices
    ++ [
      (lib.mkAliasOptionModule
        [ "my" "services" "audiobookshelf" "enable" ]
        [ "grapefruitMedia" "audiobookshelf" "enable" ]
      )
      (lib.mkAliasOptionModule
        [ "my" "services" "audiobookshelf" "enableQuickSync" ]
        [ "grapefruitMedia" "audiobookshelf" "enableQuickSync" ]
      )
      (lib.mkAliasOptionModule
        [ "my" "services" "recyclarr" "enable" ]
        [ "grapefruitMedia" "recyclarr" "enable" ]
      )
      (lib.mkAliasOptionModule
        [ "my" "services" "recyclarr" "schedule" ]
        [ "grapefruitMedia" "recyclarr" "schedule" ]
      )
      (lib.mkAliasOptionModule
        [ "my" "services" "usenet-confinement" "enable" ]
        [ "grapefruitMedia" "usenet-confinement" "enable" ]
      )
      (lib.mkAliasOptionModule
        [ "my" "media" "exporters" "enable" ]
        [ "grapefruitMedia" "exporters" "enable" ]
      )
      (lib.mkAliasOptionModule
        [ "my" "media" "exporters" "lidarr" "enable" ]
        [ "grapefruitMedia" "exporters" "lidarr" "enable" ]
      )
    ];

  config = {
    grapefruitMedia = {
      # Master-Switch folgt den Einzeldiensten — kein separates Enable in rollout.nix nötig.
      enable = lib.mkDefault anyMedia;

      domain = lib.mkDefault config.my.configs.identity.domain;

      # Ports aus der zentralen Registry (my.ports) — Werte identisch zum Altstand.
      # feishin / libreseerr / secrets-portal: Optionen entfernt (Phase 0.2 — 2026-07-15).
      # Libreseerr nativ: modules/60-apps/62-libreseerr.nix.
      ports = {
        jellyfin = lib.mkDefault config.my.ports.jellyfin;
        jellyseerr = lib.mkDefault config.my.ports.jellyseerr;
        sonarr = lib.mkDefault config.my.ports.sonarr;
        radarr = lib.mkDefault config.my.ports.radarr;
        readarr = lib.mkDefault config.my.ports.readarr;
        prowlarr = lib.mkDefault config.my.ports.prowlarr;
        sabnzbd = lib.mkDefault config.my.ports.sabnzbd;
        audiobookshelf = lib.mkDefault config.my.ports.audiobookshelf;
        navidrome = lib.mkDefault config.my.ports.navidrome;
        lidarr = lib.mkDefault config.my.ports.lidarr;
        exportarr-sonarr = lib.mkDefault config.my.ports.exportarr-sonarr;
        exportarr-radarr = lib.mkDefault config.my.ports.exportarr-radarr;
        exportarr-prowlarr = lib.mkDefault config.my.ports.exportarr-prowlarr;
        exportarr-lidarr = lib.mkDefault config.my.ports.exportarr-lidarr;
      };

      hardware = {
        ramGB = lib.mkDefault config.my.configs.hardware.ramGB;
        renderDevice = lib.mkDefault config.my.configs.hardware.renderDevice;
      };

      locale = {
        language = lib.mkDefault config.my.configs.locale.language;
        default = lib.mkDefault config.my.configs.locale.default;
      };

      storage = {
        enable = lib.mkDefault config.my.services.storage.enable;
        # poolMountPoint aus profile.nix; Fallback /data = Altstand-Pfade
        # (/data/downloads, /data/media).
        mediaRoot = lib.mkDefault (
          if config.my.services.storage.poolMountPoint != "" then
            config.my.services.storage.poolMountPoint
          else
            "/data"
        );
        # Altstand: Artwork/Metadata bewusst auf fast_pool, nicht Root-FS.
        metadataDir = lib.mkDefault "/mnt/fast_pool/metadata";
      };

      onDemand = {
        enable = lib.mkDefault config.my.policy.onDemand.enable;
        internalOffset = lib.mkDefault config.my.policy.onDemand.internalOffset;
        idleTimeoutSec = lib.mkDefault config.my.policy.onDemand.idleTimeoutSec;
      };

      vpn = {
        interface = lib.mkDefault "privado";
        dns = lib.mkDefault config.my.services.privado-vpn.dns;
      };

      # Altstand-Secrets-Verzeichnis: /var/lib/secrets (provisioniert durch
      # machines/q958/media-secrets.nix). Damit zeigen EnvironmentFile-Pfade
      # (<svc>.env, jellyseerr.env, navidrome-oidc.env) wieder auf die
      # existierenden Dateien.
      secrets.secretsDir = lib.mkDefault "/var/lib/secrets";

      # K4-Fix: Per-Service-API-Key-Pfade auf media-secrets.nix-Output mappen.
      # media-secrets.nix schreibt /var/lib/secrets/<svc>_api_key (Rohkey)
      # sowie <svc>.env (mit SONARR__AUTH__APIKEY=...).
      # Recyclarr nutzt die Rohkey-Dateien direkt (api_key._secret);
      # Exportarr nutzt LoadCredential auf dieselben Pfade.
      secrets.sonarrApiKeyFile = lib.mkDefault "/var/lib/secrets/sonarr_api_key";
      secrets.radarrApiKeyFile = lib.mkDefault "/var/lib/secrets/radarr_api_key";
      secrets.prowlarrApiKeyFile = lib.mkDefault "/var/lib/secrets/prowlarr_api_key";
      secrets.lidarrApiKeyFile = lib.mkDefault "/var/lib/secrets/lidarr_api_key";
      secrets.readarrApiKeyFile = lib.mkDefault "/var/lib/secrets/readarr_api_key";

      # K2-Fix: Auth-Proxy-Status aus q958-Config.
      # oauth2-proxy.enable kann fehlen (Option existiert nur wenn Modul aktiv) --
      # deshalb `or false` statt direktem Attribut-Zugriff.
      authProxyPresent = lib.mkDefault (
        if config ? my && config.my ? services && config.my.services ? oauth2-proxy then
          config.my.services.oauth2-proxy.enable
        else
          false
      );

      # q958 hat vollwertigen Ingress (my.ingress.fromSpec, Caddy + forward_auth).
      # Der Chamäleon-Ingress-Stub des Moduls bleibt hier aus (Review H6) —
      # sonst kollidieren vHosts im globalen Caddy.
      ingress.enable = lib.mkDefault false;

      persist.enable = lib.mkDefault config.my.impermanence.enable;
    };

    # Review-H3-Fix: persist-Pfade an den echten Impermanence-Konsumenten
    # (modules/30-storage) durchreichen statt ins Leere zu schreiben.
    my.impermanence.extraPaths = gm.persist.extraPaths;

    # Review-H2-Teilfix: UID/GID-Pins nur für tatsächlich aktive Dienste
    # (mkIf verhindert User-Anlage für deaktivierte Services).
    users.users = lib.genAttrs pinnedUsers (
      n: lib.mkIf (gm.enable && gm.${n}.enable) { uid = lib.mkForce uids.${n}; }
    );
    users.groups = lib.genAttrs pinnedUsers (
      n: lib.mkIf (gm.enable && gm.${n}.enable) { gid = lib.mkForce gids.${n}; }
    );
  };
}
