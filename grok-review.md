# grok-review.md — Abweichungen vom Zielzustand (50-media / grapefruitMedia)

**Stand:** 2026-07-15  
**Zweck:** Ausführliche Liste **was / wann / wo / wie** zu flicken ist, bis der Zielzustand steht.  
**Kein Dry-Build-Gate.** Architektur und Deklaration zuerst.  
**Code in diesem Dokument:** absichtlich weitgehend vermieden; nur wo ein Konzept sonst unklar bliebe.

Verwandte Dokus (historisch, teils veraltet bzgl. `.local`):  
`claude-review.md`, `handoff-v2.md`, `README.md` — **dieses File ist die SSoT für den Naming/DNS/Ingress-Zielzustand ab jetzt.**

---

# ████████████████████████████████████████████████████████████████████████████
# █                                                                          █
# █   !!!!!  FALLSTRICK  —  UNÜBERSEHBAR  —  VOR JEDEM DNS/INGRESS-FIX  !!!!! █
# █                                                                          █
# ████████████████████████████████████████████████████████████████████████████
#
#   .local  =  NUR Multicast im LAN (mDNS / Avahi).
#              NIEMALS in Cloudflare.
#              NIEMALS als Unicast-Rewrite in Blocky/AdGuard für „öffentliche“ Namen.
#              NIEMALS Let's-Encrypt-SAN (öffentliche CAs stellen dafür nichts aus).
#
#   *.domain.de  =  Unicast-DNS (Cloudflare + optional Split-Horizon im LAN).
#              Öffentlich (WAN) nur, was ins Netz soll.
#              Backend-Namen dürfen in der öffentlichen Zone stehen, zeigen aber
#              dynamisch auf die LAN-Adresse (192.168/172/…) — unproxied.
#              Intern optional zusätzlich Split-DNS (Blocky → LAN), wenn sinnvoll.
#
#   VERBOTENE MISCHUNGEN (klassische Bug-Quellen):
#     ✗  Cloudflare A/AAAA/CNAME für irgendetwas.local
#     ✗  Blocky customDNS: "jellyfin.local" → 192.168.…  (kollidiert mit mDNS)
#     ✗  domain-Default = "….local"  (vermischt mDNS- und Unicast-Welt)
#     ✗  Orange-Cloud (Proxy) vor Streaming-Edge (Cloudflare ToS / Streaming)
#     ✗  Stare IP-Adressen im Nix-Modul statt dynamischem DDNS-Anker
#     ✗  Caddy-Matcher nur auf name.domain → name.local antwortet nicht
#
#   RICHTIG:
#     ✓  Jeder aktivierte Dienst:  {service}.local          (immer, mDNS)
#     ✓  Wenn domain gesetzt:      {service}.{domain}       (Unicast, Caddy + DNS)
#     ✓  Cloudflare kennt nur domain.de-Namen, nie .local
#     ✓  Nur wenige CF-Anker (siehe Zielmodell „3 Routen“ unten), Rest CNAMEs
#
# ████████████████████████████████████████████████████████████████████████████

---

## 0. Zielzustand (kanonisch)

### 0.1 Namensebenen

| Ebene | Name | Wann | Auflösung | Cloudflare |
|-------|------|------|-----------|------------|
| **L1 mDNS** | `{service}.local` | **immer**, jeder enabled Service | Multicast (Avahi) | **nie** |
| **L2 Unicast** | `{service}.{domain}` | nur wenn `domain` gesetzt und nicht leer | Unicast (CF + optional Blocky) | ja, nach Tier |

Beide Namen landen am **selben** Caddy-Handle → `reverse_proxy 127.0.0.1:{port}`.  
mDNS ist **kein Fallback**, sondern **Pflicht-LAN-Identität**. Domain ist **zusätzliche** Schicht für HTTPS, SSO, WAN, DDNS.

### 0.2 Service-Tiers (L2 / Cloudflare)

#### Tier **edge-wan** — dürfen aus dem WAN erreichbar sein

DNS zeigt (über Anker, unproxied) auf **Router/WAN-IP** (DDNS).  
Cloudflare-Proxy (**orange**) für diese Streaming-/Media-UIs: **nein** (ToS / Streaming).

| Service | Status im Modul | Anmerkung |
|---------|-----------------|-----------|
| jellyfin | vorhanden | Edge |
| jellyseerr / seerr | vorhanden | Edge |
| audiobookshelf | vorhanden | Edge |
| navidrome | vorhanden | Edge |
| feishin | später / README | Edge (nativ/SPA, kein Docker-Policy-Verstoß) |
| „readmeabook“ / vergleichbare Reader-UI | später | Edge wenn UI |
| libreseerr | später / ggf. 60-apps nativ | Edge; kein `:latest`-Container in 50-media |

#### Tier **backend-lan** — Backend / Admin / Orchestration

Öffentlicher DNS-Name **erwünscht**, aber Ziel = **interne Adresse** des Media-Hosts  
(`192.168…` / `172…` / RFC1918), **unproxied**, **dynamisch per DDNS** (keine hardcodierte IP im Modul, kein manuelles Router-Port-Hopping für jeden Dienst).

Aus dem Internet: Name löst auf Private-IP → Verbindung scheitert (gewollt).  
Im LAN / VPN / split-fähigen Client: Name funktioniert ohne mDNS.

| Service | Status | Anmerkung |
|---------|--------|-----------|
| sonarr | vorhanden | Backend |
| radarr | vorhanden | Backend |
| readarr | vorhanden | Backend |
| lidarr | vorhanden | Backend |
| prowlarr | vorhanden | Backend (+ Usenet-VPN-Sandbox) |
| sabnzbd | vorhanden | Backend (+ Usenet-VPN-Sandbox) |
| recyclarr | vorhanden | kein UI-vHost nötig, kein CF-Name |
| exportarr | vorhanden | nur Metrics loopback, kein CF |
| arr-secrets-generator | vorhanden | kein vHost |
| usenet-vpn-verify | vorhanden | kein vHost |

### 0.3 Cloudflare: genau **drei** logische Routen / Anker

Nicht „pro Service ein A-Record mit starrer IP“, sondern **drei Zielklassen**.  
DDNS pflegt nur die Anker; Service-Namen hängen per **CNAME** (oder ein sauber begrenzter Wildcard-Plan) an den Ankern.

| # | Anker (Beispielname) | Proxy | Ziel (dynamisch) | Zweck |
|---|----------------------|-------|------------------|--------|
| **1** | `@` / `domain.de` | **proxied** (orange) | Landing (kann auch anderer Origin sein) | Landingpage, IP-Schutz fürs „Schaufenster“ |
| **2** | z. B. `edge` / `wan` / vereinbarter Streaming-Anker | **unproxied** (grau) | **WAN/Router-IP** via DDNS | Alle **edge-wan**-Services (CNAME → dieser Anker). Unproxied wegen **Streaming-ToS**. |
| **3** | z. B. `int` / `lan` / `media-lan` | **unproxied** (grau) | **LAN-IP des Hosts** via DDNS | Alle **backend-lan**-Services (CNAME → dieser Anker). Keine Router-Portmap pro Dienst. |

**Konsequenzen (explizit festhalten):**

- In Cloudflare stehen **keine** `.local`-Namen.
- Es stehen **keine** dutzenden A-Records mit fester Heim-IP im Nix-Code.
- Orange nur wo ToS und Streaming es erlauben (Landing); Media-Edge und Backends **grau**.
- Backend-Namen in der **öffentlichen** Zone auf Private-IP = bewusster Trade-off (Layout-Leak der LAN-IP des Media-Hosts, nicht der ganzen Topologie). Alternative später: nur Split-DNS intern — **aktuell gewollt: CF-Anker 3**.
- Router: Port-Forward nur für das, was **edge-wan** wirklich braucht (typisch 443 → Caddy), nicht für Sonarr:5003 etc.

### 0.4 Ingress / Auth / TLS (Ziel)

- Caddy **master** (global) oder **slave** (`caddy-media`), Mode `auto|global|standalone`.
- Jeder enabled UI-Dienst: Host-Matcher **`{name}.local`** und bei gesetzter Domain **`{name}.{domain}`**.
- Auth: optional `forward_auth` (oauth2-proxy / Pocket-ID); Cookie-Domain gilt für L2, **nicht** für `.local` (SSO primär auf Domain-Namen).
- TLS L2: Host-seitig lego DNS-01 (ADR-032), Media nur Cert-Pfade; L1 `.local`: HTTP oder bewusst `tls internal` — **kein** LE für `.local`.
- App-Ports: **127.0.0.1**, Firewall der App-Ports **zu**; Exposition nur über Ingress.

### 0.5 Was 50-media **autark** liefern soll vs. Host (10-network / 20-security)

| In 50-media (Standalone-Flake) | Auf dem Host / optional |
|--------------------------------|-------------------------|
| mDNS publish aller Services | Blocky DoT-Upstreams (5 Backups) |
| Caddy vHosts L1+L2, Tiers | Cloudflare API / DDNS-Updater (Anker 1–3) |
| Loopback, Hardening, Usenet-Sandbox | WireGuard-Interface (Privado) provisionieren |
| Secrets-Interface, Auth-Hooks | Pocket-ID, oauth2-proxy, ACME/lego |
| Deklaration: welcher Service welcher Tier | nftables, fail2ban, access-policy |

---

## 1. Abweichungsmatrix (Ist → Soll)

Legende Priorität:

- **P0** — Zielarchitektur blockiert / Namens- oder Sicherheits-Grundsatz verletzt  
- **P1** — Kernfeature fehlt (mDNS, Tiers, 3-Anker-Modell)  
- **P2** — Robustheit / Parität zum Original / Standalone-Härte  
- **P3** — Doku, Aufräumen, Nice-to-have  

---

### P0 — Grundlagen (zuerst)

#### P0-1 — Domain-Default vermischt mDNS und Unicast

| | |
|--|--|
| **Was** | Default `grapefruitMedia.domain = "grapefruit-media.local"` und README raten teils von `.local` ab, teils nutzen sie es als „Base domain“. Das ist genau der Fallstrick: Unicast-vHosts unter `.local`. |
| **Wo** | `default.nix` (Option `domain`); `README.md` Abschnitt DNS; `compat-my.nix` mappt ggf. Identity-Domain (ok, wenn echte Domain); Ingress baut `{name}.{domain}`. |
| **Soll** | `domain` default **leer/null** = „keine L2-Namen“. L1 läuft trotzdem. Kein Default, der auf `.local` endet. |
| **Wie** | Option auf `nullOr str` / leeren String; Ingress L2 nur bei gesetzter Domain; Doku + Fallstrick-Kommentar. |
| **Wann** | Sofort bei nächstem Options-Durchgang (vor mDNS-Implementierung oder parallel). |

#### P0-2 — README / Handoffs widersprechen dem Ziel (`.local` verboten, home.arpa)

| | |
|--|--|
| **Was** | README: „Kein `.local`“, Empfehlung `home.arpa`, Split-Horizon nur klassisch. Handoff-v2 Block 7/3.4 dasselbe. |
| **Wo** | `README.md`, `handoff-v2.md`, `claude-review-handoff.md`, Kommentare in `500-media-ingress`. |
| **Soll** | Kanon = dieser File: mDNS **immer**; Domain optional; home.arpa nicht empfohlen; 3 CF-Anker + Tiers. |
| **Wie** | README-DNS-Kapitel ersetzen; Handoffs mit Verweis auf `grok-review.md` markieren; irreführende Sätze streichen. |
| **Wann** | Parallel zu P0-1 (Doku und Options zusammen halten). |

#### P0-3 — Ingress matcht nur `{name}.{domain}`, nie `{name}.local`

| | |
|--|--|
| **Status** | **ERLEDIGT (Phase B)** — `hostList` = `{name}.local` + optional `{name}.{domain}`; Standalone `@name host …`; ohne Domain nur L1-Routen. |
| **Was war** | Nur Domain-Matcher; ohne Domain leerer Ingress. |
| **Soll** | Immer L1; L2 wenn Domain. Ein Upstream pro Dienst. |

#### P0-4 — Keine Service-Tiers (edge-wan vs backend-lan)

| | |
|--|--|
| **Was** | Alle Services werden im Ingress gleich behandelt. Keine Deklaration „WAN erlaubt“ vs „nur LAN-DNS“. Keine Anbindung an CF-Anker 2 vs 3. |
| **Wo** | `default.nix` Options; `500-media-ingress`; fehlt komplett: DNS/DDNS-Bridge. |
| **Soll** | Pro Service (oder feste Tabelle im Modul) `dnsTier = "edge-wan" | "backend-lan" | "none"`. Edge-Defaults: jellyfin, jellyseerr, audiobookshelf, navidrome (+ spätere UIs). Backend-Defaults: sonarr, radarr, readarr, lidarr, prowlarr, sabnzbd. none: recyclarr, exportarr, Generatoren. |
| **Wie** | Optionen + abgeleitete Listen `edgeServices` / `backendServices` für Doku, Assertions, und Export an Host-DDNS (siehe P1-3). |
| **Wann** | Vor Cloudflare/DDNS-Integration; sonst baut man wieder 12 A-Records. |

---

### P1 — Kernfeatures Naming / DNS / Discovery

#### P1-1 — mDNS für **alle** Services fehlt komplett

| | |
|--|--|
| **Status** | **ERLEDIGT (Phase B, 2026-07-15)** — `discovery.mdns.enable` (default true), `500-media-ingress/mdns.nix`: Avahi + `grapefruit-media-mdns-aliases` (`avahi-publish -a -R {name}.local $LAN_IP`). |
| **Was war** | Kein Avahi, kein Publish. |
| **Soll** | Default **an**. Jeder enabled UI-Service: `{service}.local` → LAN-IP. Nie Cloudflare. |
| **Scope** | Alle UI-Services inkl. Backend-UIs (Sonarr etc.); kein recyclarr/exportarr. |

#### P1-2 — Domain-Option und leerer Domain-Zustand

| | |
|--|--|
| **Was** | Domain ist Pflicht-String mit schlechtem Default; Standalone ohne echte Domain erzwingt Fake-Unicast. |
| **Wo** | `default.nix`, Ingress, Navidrome OIDC (`auth.${domain}`), Jellyfin-Seeds (`https://jellyfin.${domain}`). |
| **Soll** | Ohne Domain: nur L1; OIDC/absolute URLs deaktiviert oder warnen; mit Domain: L2 + optionale OIDC-URLs. |
| **Wie** | Bedingte Config; Warnings statt stiller `auth..well-known` auf Quatsch-Domain. |
| **Wann** | Mit P0-1. |

#### P1-3 — Cloudflare-3-Anker-Modell ist nirgends modelliert

| | |
|--|--|
| **Was** | Kein Export „welche Namen → edge-Anker / lan-Anker“. DDNS liegt im Host (`10-network/1003-gateway` etc.), 50-media weiß nichts von Ankern. |
| **Wo** | Neu in 50-media: Options `grapefruitMedia.dns.cloudflare` oder `discovery.unicast`; Bridge in Host-Modul oder optionales Submodul. |
| **Soll** | Modul deklariert: Anker-Namen (konfigurierbar), Tier-Zuordnung, CNAME-Soll-Liste. **Ein** DDNS-Job aktualisiert WAN-IP (Anker 2), **ein** Job LAN-IP (Anker 3). Landing (Anker 1) separat/Host. Keine hardcodierte `192.168.2.250` im Flake. |
| **Wie** | LAN-IP dynamisch aus `config.networking…` / profile / runtime (z. B. primäres LAN-Interface), geschrieben von DDNS-Updater (qdm12 o. Ä. kann Private-IP tracken oder kleines Script + CF API). WAN weiter wie bestehendes DDNS. 50-media liefert nur die **Namenliste + Tier**, implementiert idealerweise **nicht** zwingend den CF-Client (Host darf), muss aber das **Interface** haben für Standalone-Doku und optionalen Hook. |
| **Wann** | Nach P0-4 und P1-1; mit Host-Team (10-network) abstimmen. |
| **Nicht** | Pro Service Port-Forward am Router. |

#### P1-4 — Ingress kennt keine Unterscheidung WAN-Härtung pro Tier

| | |
|--|--|
| **Was** | Wenn Ports 80/443 am Router offen sind, sind **alle** vHosts theoretisch WAN-erreichbar, sobald DNS auf WAN zeigt. Backend-Namen zeigen zwar auf LAN-IP (Anker 3), aber falscher CF-Eintrag (Backend aus Versehen auf Anker 2) = Backend im Internet. |
| **Wo** | Ingress + optional Caddy-Matcher (IP allow) + Doku. |
| **Soll** | Defense in depth: (1) DNS-Tier korrekt, (2) optional `edge-wan` ohne Extra; `backend-lan` zusätzlich nur private RemoteIP / fail closed wenn Direct von WAN — **optional**, nicht Pflicht wenn DNS-Tier strikt. |
| **Wie** | Mindestens Assertions/Warnings wenn backend-Service fälschlich als edge markiert; optional Caddy `remote_ip` private ranges für backend vHosts. |
| **Wann** | Mit P0-4 / P1-3. |

#### P1-5 — Landingpage (CF-Anker 1) fehlt in 50-media

| | |
|--|--|
| **Was** | Kein Landing-vHost für Apex; liegt vermutlich außerhalb. |
| **Wo** | Host/Caddy global oder kleines optionales `ingress.landing`. |
| **Soll** | Nicht zwingend in 50-media; in Zielarchitektur dokumentieren: Anker 1 = Host-Landing, proxied. Media-Modul darf optional `enableLanding = false` lassen. |
| **Wie** | README + dieses File; nur wenn Standalone-Alles-aus-einer-Hand: minimaler respond/static. |
| **Wann** | Doku jetzt; Code nur bei Bedarf. |

---

### P1 — Ingress-Technik (noch offen trotz Phase-3-Bugfixes)

*Hinweis: Bug1–4 in `500-media-ingress` (enabledServices-Filter, forward_auth-Syntax, skipPaths, tls custom :443) gelten als **adressiert** im Tree — unten nur Restlücken.*

#### P1-6 — Caddyfile-Adapter / ExecStart

| | |
|--|--|
| **Was** | `caddy run --config` auf geschriebenem Caddyfile ohne `--adapter caddyfile` (je nach Caddy-Version riskant). |
| **Wo** | `500-media-ingress/default.nix` ExecStart. |
| **Soll** | Explizit Caddyfile-Adapter oder JSON-Config. |
| **Wie** | Flag ergänzen; validate-Befehl in Doku. |
| **Wann** | Bei nächster Ingress-Session. |

#### P1-7 — Global-Mode: nur ein vHost-Key pro Service (Domain)

| | |
|--|--|
| **Status** | **ERLEDIGT (Phase B)** — `http://{name}.local` (kein ACME) + optional `{name}.{domain}`; Assertion gegen `domain` endet auf `.local`. |
| **Was war** | Nur Domain-Key, und nur bei hasDomain. |
| **Soll** | L1 immer (HTTP); L2 ACME-fähig am Host. |

#### P1-8 — Auth/SSO: Pocket-ID / oauth2-proxy nur als Hook, Master/Slave unvollständig dokumentiert

| | |
|--|--|
| **Was** | `forwardAuthUpstream` + `authProxyPresent` existieren; kein First-Class „Slave hängt an Host-Master-Auth“. Cookie-Domain vs `.local` undokumentiert im Modul. |
| **Wo** | `default.nix` ingress.auth; `520` AUTH__METHOD; Host `2028-oauth2-proxy`, `1001-pocket-id`. |
| **Soll** | Doku: SSO primär über L2; L1 Forms oder ohne; `authProxyPresent` aus Host-Compat. Standalone: User setzt forward-auth URL. |
| **Wie** | README Auth-Matrix; keine Pflicht, IdP in 50-media zu vendoren. |
| **Wann** | Mit Naming-Doku. |

#### P1-9 — compat-my setzt `ingress.enable = false` auf q958

| | |
|--|--|
| **Was** | q958 nutzt Host-Ingress (`my.ingress.fromSpec`); Chamäleon absichtlich aus. Dann greifen **keine** 500-Fixes für vHosts — Host-Generator muss L1+L2+Tiers lernen. |
| **Wo** | `compat-my.nix`; Host `1094-ingress` + `lib/caddy-ingress.nix` / `service-enable` / `dns-map`. |
| **Soll** | Entweder (A) Host-Ingress erzeugt dieselben Hosts (`.local` + domain + Tiers), oder (B) Media-Ingress injectet partial vHosts ohne Konflikt. Entscheidung dokumentieren. |
| **Wie** | Architektur-Entscheidung in diesem File + Host-Issues; nicht stillschweigend nur 50-media fixen und q958 vergisst mDNS. |
| **Wann** | Sobald mDNS/L2 in 50-media steht — **Host-Parität** als eigener Track. |

---

### P2 — Security / VPN / Secrets / Parität Original

#### P2-1 — Usenet-VPN: Default-DNS `1.1.1.1` statt Provider-DNS

| | |
|--|--|
| **Was** | Regression ggü. Original (`privado.dns` → usenet-resolv). |
| **Wo** | `default.nix` `vpn.dns`; `590-usenet-confinement`. |
| **Soll** | Kein stiller Public-DNS-Default; bei confinement: DNS-Liste **gesetzt** (aus VPN-Profil/compat), sonst Warning/Assert. Interface bleibt parametrisiert (`privado`). |
| **Wie** | Default `[]`; assertion wenn enable && dns==[]; compat mappt `privado-vpn.dns`. |
| **Wann** | Kleiner Fix, jederzeit. |

#### P2-2 — Usenet-Confinement ohne „Interface existiert“-Diagnose

| | |
|--|--|
| **Was** | Kein WireGuard in 50-media (richtig); bei enable ohne Interface: stilles Warten auf device unit. |
| **Wo** | `590`; optional Warning. |
| **Soll** | Warning/Assert-Text: „Interface `${vpn.interface}` muss von Host/VPN-Modul kommen (Privado)“. Optional `OnFailure` → Alerting-Hook (Option, default null). |
| **Wie** | Message only + optional onFailureUnit. |
| **Wann** | Mit P2-1. |
| **Nicht** | Anderes VPN erfinden; Netbird ≠ Usenet-Sandbox. |

#### P2-3 — EnvironmentFile *arr ohne `-`-Prefix

| | |
|--|--|
| **Was** | Fehlt `.env`, startet Dienst hart. Jellyseerr hat `-`. |
| **Wo** | `520-arr-stack/default.nix`, `on-demand.nix`. |
| **Soll** | Tolerant oder Ordering mit secrets-generator / sops. |
| **Wie** | `-path` und/oder `before=` / `Requires=` Generator. |
| **Wann** | Vor „autoGenerate Homelab“-Empfehlung. |

#### P2-4 — Secrets-Generator: root, alle Services, wenig Hardening

| | |
|--|--|
| **Was** | Funktionale K4-Fixes (per-Service, AUTH__APIKEY) ok; Betriebs-Härte nein. |
| **Wo** | `520-arr-stack/secrets-generator.nix`. |
| **Soll** | Nur enabled Services; engere Permissions; optional hardening. |
| **Wann** | P2. |

#### P2-5 — Deklarative Provisionierung (arr-sync) fehlt

| | |
|--|--|
| **Was** | Original `56-arr-sync` (Keys→config, Download-Clients, Indexer, Seerr, Jellyfin-Bootstrap) nicht portiert. Scope-Cut ADR-5034. |
| **Wo** | Fehlt unter 50-media; `packages/arr-provision` im Haupt-Repo. |
| **Soll** | Phase später: optionales Layer oder Flake-Input; bis dahin README „manuelle Erstkonfiguration“. |
| **Wann** | **Nach** Naming/Ingress/DNS-Tiers (P0/P1). Nicht mit mDNS vermischen. |

#### P2-6 — Exportarr ohne Scrape-Bridge / OnFailure-Alerting VPN

| | |
|--|--|
| **Was** | Exporter da; Host-VM-Scrape und Leak-Alerting aus Original abgeschwächt. |
| **Wo** | `570`; `590`; Host Observability. |
| **Soll** | Optionale Hook-Optionen (`onFailureUnit`, scrape labels export). |
| **Wann** | P2, nach Kern. |

#### P2-7 — On-Demand-Pfad schwächer gehärtet / Exportarr-after

| | |
|--|--|
| **Was** | Backend-Units nicht voll factory-parität; Exportarr `after=lidarr.service` bei on-demand fraglich. |
| **Wo** | `520-arr-stack/on-demand.nix`, `lib/on-demand-http.nix`, `570`. |
| **Soll** | Bind 127.0.0.1, Hardening angleichen; Dependencies auf `*-backend` wenn on-demand. |
| **Wann** | P2. |

#### P2-8 — Jellyfin Config-Seeds überschreiben UI-Edits

| | |
|--|--|
| **Was** | `cmp` + install bei Seed-Drift. |
| **Wo** | `510-jellyfin`. |
| **Soll** | Dokumentieren oder nur seed-if-missing für manche Files. |
| **Wann** | P3/P2 je nach Schmerz. |

#### P2-9 — Standalone-Security-Baseline vs. 20-security

| | |
|--|--|
| **Was** | Autarkie-Ziel: ohne 20-security nicht „offen“. Aktuell: Loopback + factory gut; kein gebündeltes „Baseline-Checklist-Modul“. |
| **Wo** | Doku + Assertions-Sammlung. |
| **Soll** | Checkliste in README: openFirewall false, bind loopback, auth modes, usenet sandbox, keine CF-.local, edge unproxied, backend LAN-Anker. Optional `grapefruitMedia.assertions.strict = true`. |
| **Wann** | Doku mit P0; Assertions schrittweise. |

#### P2-10 — Tote Prototypen / Import-Leichen

| | |
|--|--|
| **Was** | 551/580/591 aus Imports; Dateien ggf. noch im Tree oder schon weg; handoff Phase 0.2. |
| **Wo** | Tree-Cleanup. |
| **Soll** | Entfernen oder klar „future native“ nur in README. |
| **Wann** | P3 Cleanup. |

---

### P3 — Doku, UX, spätere Features

#### P3-1 — Spätere Edge-Services (Feishin, Libreseerr, …)

| | |
|--|--|
| **Was** | In Ziel-Tier edge-wan, im Modul nicht/nur geplant. |
| **Wo** | README Roadmap; später eigene 5xx. |
| **Soll** | Nativ/SPA+Caddy, POL-FT-001 kein Docker; Tier edge-wan; mDNS + Domain. |
| **Wann** | Nach stabilem Naming/DNS. |

#### P3-2 — `hardeningProfile = "node"` ohne Profil-Zweig

| | |
|--|--|
| **Was** | ABS setzt `node`, Factory kennt full/dotnet/streamer. |
| **Wo** | `lib/service-factory.nix`, `540`. |
| **Soll** | Profil ergänzen oder umbenennen. |
| **Wann** | Nit. |

#### P3-3 — enableQuickSync-README-Falschaussage

| | |
|--|--|
| **Was** | README behauptet Bezug zu Jellyfin; Code steuert ABS. |
| **Wo** | `README.md`. |
| **Wann** | Mit README-Rewrite P0-2. |

#### P3-4 — memory-policy Kommentar verweist noch auf `my.configs`

| | |
|--|--|
| **Was** | Vendored Lib-Kommentar veraltet. |
| **Wo** | `lib/memory-policy.nix`. |
| **Wann** | Nit. |

#### P3-5 — Verschlüsseltes Host-DNS (5 DoT-Upstreams)

| | |
|--|--|
| **Was** | Liegt in 10-network Blocky, nicht in 50-media — **richtig**. |
| **Soll** | README: „Host liefert DoT; Media rührt :53 nicht an; Usenet nur vpn.dns.“ Optional Standalone-Hinweis ohne Implementierungszwang. |
| **Wann** | Doku P0-2. |

---

## 2. Cloudflare / DDNS — Sollbild „3 Routen“ im Detail

### 2.1 Was „3 Routen“ heißt

| Route | Proxy | DDNS-Ziel | Wer hängt dran |
|-------|-------|-----------|----------------|
| **1 Landing** | orange | Origin Landing (oder statisch) | nur Apex / Marketing |
| **2 Edge** | **grau** (Pflicht, Streaming-ToS) | **öffentliche IP des Routers** (dynamisch) | jellyfin, seerr, audiobookshelf, navidrome, (+ später Feishin, Libreseerr, …) als **CNAME → Anker-2** |
| **3 Backend** | **grau** | **LAN-IP des Media-Hosts** (dynamisch, 192.168/172/…) | sonarr, radarr, readarr, lidarr, prowlarr, sabnzbd, … als **CNAME → Anker-3** |

Damit bleiben **zwei DDNS-Updater-Ziele** (WAN + LAN) + Landing — nicht zwölf manuelle A-Records.

### 2.2 Was 50-media dafür liefern muss

1. Feste/konfigurierbare **Tier-Map** pro Service.  
2. Generierte Liste: `CNAME jellyfin → edge-Anker`, `CNAME sonarr → lan-Anker`, …  
3. **Keine** Implementierungspflicht des Cloudflare-API-Clients im Minimal-Standalone — aber Options + Doku + optional Hook `dns.records` für den Host.  
4. Garantie: **kein** Generator schreibt jemals `*.local` nach CF.

### 2.3 Was der Host (10-network) liefern muss

1. DDNS Anker-2 ← öffentliche IP (bestehendes ddns-updater-Muster).  
2. DDNS Anker-3 ← aktuelle LAN-IP des Servers (neu oder erweitern; **dynamisch**).  
3. Optional: einmalig/declarative CNAME-Sync aus Media-Export (oder manuell 1× anlegen, Anker-IPs laufen per DDNS).  
4. Port-Forward nur für Edge-Bedarf (443→Caddy), nicht Backend-Ports.

### 2.4 Router

- **Kein** „für jeden *arr einen Port im Router“.  
- Edge: klassisch 443 (und ggf. 80) zum Host mit Caddy.  
- Backend: Erreichbarkeit über LAN-IP-DNS + gleiches Caddy im LAN; von WAN aus Private-IP = tot (ok).

### 2.5 Bewusster Trade-off (nicht „Bug“)

Öffentliche DNS-Namen → Private IP (Anker 3) leaken die **Media-Host-LAN-IP** an jeden, der die Zone abfragt.  
Das ist **akzeptiert** zugunsten von Bequemlichkeit (kein Router-Gefummel, dynamisch, wenige Anker).  
**Nicht** akzeptiert: `.local` in CF, orange Streaming, starre IPs im Nix.

---

## 3. Reihenfolge der Arbeit (empfohlen)

```text
Phase A — Prinzipien & Options (P0-1, P0-2, P0-4)
  Domain null-fähig; README/Fallstrick; Tier-Tabelle als Optionen/SSoT

Phase B — Erreichbarkeit LAN (P1-1, P0-3, P1-7)
  mDNS alle Services; Caddy host .local + optional .domain

Phase C — Unicast-Anker (P1-3, P1-4, P1-5 Doku)
  3-Routen-Modell; Export CNAME/Tier; Host-DDNS WAN+LAN

Phase D — Host-Parität q958 (P1-9)
  compat/ingress-fromSpec oder Media-inject

Phase E — Security-Rest (P2-1 … P2-4, P2-9)
  VPN-DNS, EnvFiles, Baseline-Assertions

Phase F — Feature-Parität Original (P2-5, P2-6, P3-1)
  arr-provision, Observability, Feishin/Libreseerr nativ
```

---

## 4. Checkliste „Ziel erreicht?“

- [ ] **Fallstrick** in README + Modul-Header referenziert; kein Default-Domain auf `.local`
- [x] Jeder enabled UI-Service: mDNS `{service}.local` + Caddy-Matcher (Phase B)
- [x] Caddy matcht **beide** Hostnames (L1 immer, L2 bei Domain)
- [ ] Mit Domain: HTTPS unter `{service}.{domain}` (Cert Host/lego — Host/Phase C)
- [ ] Cloudflare: **keine** `.local`-Records
- [ ] CF: Landing proxied; Edge-Anker unproxied→WAN-DDNS; Backend-Anker unproxied→LAN-DDNS
- [ ] Edge-Services CNAME→Anker 2; Backend-Services CNAME→Anker 3
- [ ] Keine starre Heim-IP in 50-media
- [ ] Streaming-Edge **nicht** orange geproxied
- [ ] App-Ports nur loopback; Usenet nur über VPN-Interface + sinnvolle vpn.dns
- [ ] q958: entweder Media-Ingress oder Host-Ingress mit **gleicher** Host-Semantik
- [ ] Spätere UIs (Feishin, Libreseerr, …) in Tier-Tabelle als edge-wan vorbereitet

---

## 5. Explizit **nicht** mehr Ziel (verworfene Review-Ideen)

| Verworfen | Stattdessen |
|-----------|-------------|
| „Kein `.local` / nimm home.arpa“ | mDNS **immer** `.local` |
| mDNS nur als Fallback | mDNS = L1 Pflicht |
| Pro Service eigener CF-A mit fester IP | 3 Anker + CNAME + dynamisches DDNS |
| Backend nur „gar nicht in öffentlicher DNS“ | Backend **mit** öffentlichem Namen → LAN-IP (Anker 3) |
| Dry-Build als Merge-Gate (jetzt) | Architektur zuerst; Build wenn NixOS wieder da |
| Media-Modul baut Privado-WG selbst | Host 1096; Media nur confinement + Interface-Name |
| Media betreibt Host-DoT/Blocky | Host 1002; Media nur usenet resolv |

---

## 6. Kurz: Abweichung in einem Satz

**Heute:** Unicast-only-Ingress auf einer Domain (Default fälschlich `.local`), **kein** mDNS, **keine** Edge/Backend-Tiers, **kein** 3-Anker-Cloudflare-Modell, VPN-DNS-Default unsauber, Host-Ingress auf q958 entkoppelt.  

**Soll:** L1 mDNS **alle** Services + L2 Domain mit Tier edge-wan (DDNS→Router, unproxied) vs backend-lan (DDNS→LAN-IP, unproxied) + Landing proxied — **drei** Cloudflare-Routen, null `.local` in CF, null starre IPs im Modul.

---

*Ende grok-review.md — bei Zielkonflikten gewinnt dieser File vor handoff-v2/README bis die dort angepasst sind.*
