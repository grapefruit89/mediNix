# grapefruitMedia — Standalone NixOS Media Stack

Portables NixOS-Modul für den kompletten Heimmedien-Stack:
Jellyfin · Sonarr · Radarr · Lidarr · Readarr · Prowlarr · SABnzbd · Audiobookshelf · Navidrome.

## Quickstart (fremdes System)

```nix
# flake.nix
{
  inputs.mediNix.url = "github:grapefruit89/mediNix";
  # ...

  nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
    modules = [
      mediNix.nixosModules.grapefruit-media
      {
        grapefruitMedia = {
          enable   = true;
          domain   = "media.example.com";

          jellyfin.enable  = true;
          sonarr.enable    = true;
          radarr.enable    = true;
          prowlarr.enable  = true;
          sabnzbd.enable   = true;

          secrets.autoGenerate = true;   # API-Keys beim Start erzeugen

          ingress = {
            enable = true;
            mode   = "standalone";       # eigener caddy-media Service
          };
        };
      }
    ];
  };
}
```

Nach `nixos-rebuild switch`: Dienste laufen auf `127.0.0.1`, Ingress auf `:80`.

---

## Wichtige Optionen

| Option | Default | Beschreibung |
|--------|---------|--------------|
| `grapefruitMedia.enable` | `false` | Modul aktivieren |
| `grapefruitMedia.domain` | `grapefruit-media.local` | Base-Domain für vHosts |
| `grapefruitMedia.storage.mediaRoot` | `/data` | Basis für Downloads + Mediathek |
| `grapefruitMedia.storage.metadataDir` | `/var/lib/media-metadata` | Artwork-Cache |
| `grapefruitMedia.secrets.autoGenerate` | `false` | API-Keys automatisch erzeugen |
| `grapefruitMedia.authProxyPresent` | `false` | `true` wenn oauth2-proxy/Pocket-ID aktiv |
| `grapefruitMedia.ingress.mode` | `"auto"` | `auto`/`standalone`/`global` |
| `grapefruitMedia.ingress.auth.mode` | `"none"` | `none`/`forward-auth` |
| `grapefruitMedia.ingress.tls.mode` | `"off"` | `off`/`internal`/`custom` |

### Secrets-Modell

Zwei Modi:

**autoGenerate = true** (Entwicklung/Homelab):
```nix
grapefruitMedia.secrets.autoGenerate = true;
# Erzeugt /var/lib/media-secrets/{sonarr,radarr,...}.env beim Start.
# Idempotent: bestehende Keys werden nicht überschrieben.
```

**Extern / sops-nix** (Produktion):
```nix
grapefruitMedia.secrets = {
  autoGenerate = false;
  sonarrApiKeyFile   = "/run/secrets/sonarr_api_key";
  radarrApiKeyFile   = "/run/secrets/radarr_api_key";
  prowlarrApiKeyFile = "/run/secrets/prowlarr_api_key";
  lidarrApiKeyFile   = "/run/secrets/lidarr_api_key";
  readarrApiKeyFile  = "/run/secrets/readarr_api_key";
};
```

### Ingress: Auth (forward_auth)

```nix
grapefruitMedia = {
  authProxyPresent = true;   # schaltet *arr AUTH__METHOD=External
  ingress.auth = {
    mode           = "forward-auth";
    forwardAuthUrl = "http://127.0.0.1:4180/oauth2/auth";
    skipPaths      = [ "/metrics" "/health" ];
  };
};
```

Caddy generiert dann für jeden Dienst:
```
handle @sonarr {
  forward_auth http://127.0.0.1:4180/oauth2/auth
  reverse_proxy http://127.0.0.1:5003
}
```

### Ingress: TLS

```nix
# Internes Selbstsigniertes Cert (gut für lokale Entwicklung):
grapefruitMedia.ingress.tls.mode = "internal";

# Externes Cert (von security.acme/lego, ADR-032):
grapefruitMedia.ingress.tls = {
  mode     = "custom";
  certFile = "/var/lib/acme/media.example.com/cert.pem";
  keyFile  = "/var/lib/acme/media.example.com/key.pem";
};
# KEIN ACME im Modul selbst (Separation of Concerns, ADR-032).
# lego/security.acme läuft auf Host-Ebene.
```

---

## DNS & Namensschema

### Was NICHT verwenden

**Kein `.local`** — `.local` ist für mDNS/Bonjour reserviert (RFC 6762).
Browser und Avahi/systemd-resolved konkurrieren darum → unzuverlässig.

### Empfohlenes Setup: Eigene Domain mit Split-Horizon

```
Domain: media.example.com  (oder sub.yourdomain.de)

Intern:  Blocky/AdGuard-Rewrite → LAN-IP des Servers
Extern:  Cloudflare DDNS        → WAN-IP (optional)
TLS:     lego DNS-01 Wildcard   → *.media.example.com
```

**Blocky-Rewrite** (in `services.blocky`):
```yaml
customDNS:
  mapping:
    jellyfin.media.example.com: 192.168.1.100
    sonarr.media.example.com:   192.168.1.100
    # … oder Wildcard wenn Blocky das unterstützt
```

**lego DNS-01 Wildcard** via `security.acme` (NixOS):
```nix
security.acme = {
  acceptTerms = true;
  email = "admin@example.com";
  certs."media.example.com" = {
    extraDomainNames = [ "*.media.example.com" ];
    dnsProvider = "cloudflare";
    credentialsFile = "/run/secrets/cloudflare.env";
  };
};

grapefruitMedia.ingress.tls = {
  mode     = "custom";
  certFile = "/var/lib/acme/media.example.com/fullchain.pem";
  keyFile  = "/var/lib/acme/media.example.com/key.pem";
};
```

### Alternative: `.home.arpa` (RFC 8375)

Für rein interne Setups ohne eigene Domain:
```nix
grapefruitMedia.domain = "grapefruit-media.home.arpa";
```
`.home.arpa` ist der offizielle RFC-8375-Namespace für Heimnetzwerke.
Keine Kollision mit mDNS. Lokaler DNS-Resolver (Blocky/dnsmasq) muss
die Zone auflösen — kein automatisches Discovery wie bei `.local`.

---

## Grenzen

- **Provisionierung (arr-sync):** Deklarative Konfiguration von Indexern,
  Download-Clients, API-Key-Injection — Phase 1 (noch nicht implementiert).
  Bis dahin: manuelle Erstkonfiguration im UI.
- **Feishin:** Native SPA-Implementierung noch ausstehend (Phase 5).
- **GPU-Transcoding:** Jellyfin QuickSync-Mapping via `audiobookshelf.enableQuickSync`
  (falsch benannt — betrifft Jellyfin). Erfordert `hardware.renderDevice`.
- **Tests:** `nix flake check` mit VM-Test kommt in Phase 5.

---

## Architektur-Entscheidungen

Relevante ADRs im Haupt-Repo (`grapefruit89/Nix-Grok`):

| ADR | Thema |
|-----|-------|
| ADR-032 | OS-native-first: TLS via security.acme, nicht Caddy-ACME |
| ADR-011 | UID=Port=FolderPrefix Schema (4-stellig) |
| ADR-5030 | Media-Stack-Factory-Hardening (DotNet-Profil) |
| ADR-5033 | On-Demand-Socket-Aktivierung (Lidarr/Readarr) |
| ADR-5034 | Scope-Cut arr-provision (Phase 1 pending) |
