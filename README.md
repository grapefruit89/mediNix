# grapefruitMedia — Standalone NixOS Media Stack

Portables NixOS-Modul für den kompletten Heimmedien-Stack:
Jellyfin · Sonarr · Radarr · Lidarr · Readarr · Prowlarr · SABnzbd · Audiobookshelf · Navidrome.


> **Neue Maschine?** `50-core/ONBOARDING.md` führt von der leeren Maschine bis
> zu elf laufenden Diensten — sieben Schritte, jeder mit seiner Prüfung.

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
| `grapefruitMedia.domain` | `null` | Optionale L2-Unicast-Domain für vHosts (`{service}.{domain}`). `null`/`""` = nur mDNS `{service}.local`. **Nie** auf `.local` enden lassen. |
| `grapefruitMedia.discovery.mdns.enable` | `true` | Avahi: publiziert `{service}.local` → LAN-IP für alle enabled UI-Dienste. **Nie** in Cloudflare. |
| `grapefruitMedia.discovery.mdns.openFirewall` | `true` | UDP 5353 für mDNS öffnen. |
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
    mode                = "forward-auth";
    forwardAuthUpstream = "http://127.0.0.1:4180";  # Upstream ohne Pfad
    forwardAuthUri      = "/oauth2/auth";            # default: /oauth2/auth
    skipPaths           = [ "/metrics" "/health" ];
  };
};
```

Caddy generiert dann für jeden Dienst (korrekte Caddy-Syntax per Doku):
```
handle @sonarr {
  forward_auth http://127.0.0.1:4180 {
    uri /oauth2/auth
    copy_headers Remote-User Remote-Email Remote-Groups X-Auth-Request-User X-Auth-Request-Email
  }
  reverse_proxy http://127.0.0.1:5003
}
```

Bei `skipPaths` (z.B. für native App-APIs die kein Cookie nutzen):
```
handle @sonarr {
  @sonarrSkip path /metrics /health
  handle @sonarrSkip {
    reverse_proxy http://127.0.0.1:5003
  }
  handle {
    forward_auth http://127.0.0.1:4180 {
      uri /oauth2/auth
      copy_headers Remote-User Remote-Email Remote-Groups
    }
    reverse_proxy http://127.0.0.1:5003
  }
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

> **Kanon:** `lib/registry.nix` ist die einzige Wahrheit für Port, UID, Tier
> und mDNS-Menge. Ports folgen der Ordnernummer × 10 (Sonarr 512 → 5120).
>
> Ältere Dokumente unter `50-core/archiv/` beanspruchen diese Rolle teils für sich
> (`grok-review.md`: „SSoT für Naming/DNS/Ingress"). **Das gilt nicht mehr.**
> Sie sind aufgehoben, weil Code-Kommentare auf ihre Befunde verweisen — nicht,
> weil ihr Zielzustand noch aktuell wäre.

### Zwei Namensebenen

| Ebene | Name | Wann | Auflösung | Cloudflare |
|-------|------|------|-----------|------------|
| **L1 mDNS** | `{service}.local` | **immer**, jeder enabled UI-Dienst | Multicast (Avahi) | **nie** |
| **L2 Unicast** | `{service}.{domain}` | nur wenn `domain` gesetzt | Unicast (Cloudflare + optional Blocky) | ja, nach Tier |

`.local` ist **Pflicht-LAN-Identität** (nicht Fallback) — **Phase B ist live:**
Avahi + `grapefruit-media-mdns-aliases` publizieren `{service}.local` → **LAN-IP**
(dynamisch, kein Hardcode). Caddy matcht **immer** `{service}.local` und bei
gesetzter Domain zusätzlich `{service}.{domain}` (ein Upstream pro Dienst).

**TLS-Verhalten (Standalone):**
- `tls.off` — L1 + L2 auf `:80`
- `tls.internal` — L1 + L2 auf `:443` (Caddy-interne CA; Browser-Warnung ok)
- `tls.custom` — L1 bleibt HTTP auf `:80` (öffentliches Cert matcht `.local` nicht);
  L2 auf `:443` mit lego/ACME-Pfaden

**Global-Caddy:** vHost `http://{service}.local` (kein ACME) + optional
`{service}.{domain}` (Host kann `useACMEHost` setzen).

**Fallstrick (unverhandelbar):** `.local` gehört **ausschließlich** ins
Multicast-LAN. Niemals in Cloudflare, niemals als Unicast-Rewrite in
Blocky/AdGuard, niemals als Let's-Encrypt-SAN. `domain` **nie** auf `.local`
enden lassen — Modul-Assertion bricht die Eval sonst ab.

### Service-Tiers (L2 / Cloudflare)

Feste SSoT: `lib/service-tiers.nix`.

| Tier | Bedeutung | Services (Default) |
|------|-----------|--------------------|
| **edge-wan** | WAN-erreichbar, CNAME → CF-Anker 2 (WAN-IP, **unproxied** — Streaming-ToS) | jellyfin, jellyseerr, audiobookshelf, navidrome |
| **backend-lan** | nur LAN-DNS, CNAME → CF-Anker 3 (LAN-IP, unproxied) | sonarr, radarr, readarr, lidarr, prowlarr, sabnzbd |
| **none** | kein vHost / kein CF-Name | recyclarr, exportarr |

### Cloudflare: genau drei Routen

Kein A-Record-je-Service mit starrer IP, sondern **drei Anker** (DDNS pflegt
nur diese, Service-Namen hängen per CNAME dran):

1. **Landing** (`@`/Apex) — **proxied** (orange), Host-Sache (nicht 50-media).
2. **Edge-Anker** — **unproxied** (grau) → WAN-IP via DDNS. Alle edge-wan-Services.
3. **Backend-Anker** — **unproxied** → LAN-IP des Hosts via DDNS. Alle backend-lan-Services.

50-media liefert nur **Namensliste + Tier** (SSoT oben). DDNS, CF-Records und
Router-Port-Forward (nur 443 für Edge) macht der Host (`10-network`). **Keine**
starre Heim-IP im Modul, **kein** `.local` in Cloudflare.

### TLS für L2

Extern via `security.acme`/lego (DNS-01, ADR-032), Modul bekommt nur Cert-Pfade
(`ingress.tls.mode = "custom"`). `.local` (L1) läuft HTTP oder bewusst
`tls internal` — **kein** Let's-Encrypt für `.local`.

---

## Grenzen

- **Provisionierung (arr-sync):** Deklarative Konfiguration von Indexern,
  Download-Clients, API-Key-Injection — Phase 1 (noch nicht implementiert).
  Bis dahin: manuelle Erstkonfiguration im UI.
- **Feishin:** Native SPA-Implementierung noch ausstehend (Phase 5).
- **GPU-Transcoding:** `audiobookshelf.enableQuickSync` steuert das Intel-QSV-
  Mapping für **Audiobookshelf** (nicht Jellyfin). Erfordert `hardware.renderDevice`.
- **Tests:** `nix flake check` mit VM-Test kommt in Phase 5.

---

## Troubleshooting

| Symptom | Ursache & Lösung |
|---------|------------------|
| `The option 'my.services.jellyfin' does not exist` | Altes `my.*`-Schema. Dieses Modul nutzt `grapefruitMedia.jellyfin.enable`. |
| Build bricht: `vpn.dns ist leer` | Beabsichtigt (fail-closed). Setze einen Resolver, der **durch den Tunnel** erreichbar ist, z.B. den DNS des VPN-Providers. Nicht den Host-Resolver — das wäre ein DNS-Leak. |
| `tls.mode = "custom"` ohne Zertifikat | `ingress.tls.certFile` + `keyFile` setzen, oder auf `"internal"`/`"off"` wechseln. |
| `avahi-publish: No working network interface` | Kein LAN-Interface aktiv. Prüfen mit `ip route get 1.1.1.1`. |
| `{service}.local` geht nicht über WireGuard | Systembedingt: mDNS ist L2-Multicast und passiert keinen L3-Tunnel. Über VPN `{service}.{domain}` nutzen. |
| `{service}.local` geht auf dem Fire TV / Smart-TV nicht | Manche Android-/Fire-OS-Versionen lösen `.local`-Hostnamen nicht über die normalen DNS-APIs auf. Dann `{service}.{domain}` nutzen (LAN-IP via Wildcard). |
| Edge-Dienst aus dem LAN nicht erreichbar | Edge-Namen haben einen eigenen A-Record auf die WAN-IP (spezifisch schlägt Wildcard) → der Router braucht **Hairpin-NAT**. Alternative: `.local`. |
| *arr fordert Login trotz Auth-Proxy | `grapefruitMedia.authProxyPresent = true` setzen, damit `AUTH__METHOD=External` greift. |
| Passkey-Login auf `.local` schlägt fehl | Ohne gültiges HTTPS kein Secure Context — WebAuthn verweigert. Für Passkeys `{service}.{domain}` nutzen. |
| Dienst startet nicht, `.env` fehlt | Kein Problem: EnvironmentFile hat `-`-Prefix, fehlende Dateien werden ignoriert. Prüfe stattdessen `secrets.autoGenerate` oder die externen Secret-Pfade. |

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
