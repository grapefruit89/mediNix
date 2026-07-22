# Network topology — who reaches what, and from where

Overview of the reachability model: LAN, WAN, WireGuard, mDNS/`.local`,
Cloudflare and Let's Encrypt. Written in English so it is usable for outside
collaborators.

**Core principle:** every service binds to `127.0.0.1` only. Nothing is reachable
without passing through the Caddy ingress — `.local` included. A direct
`192.168.x.y:5003` never works.

---

## 1. Reachability matrix

| From | `{service}.{domain}` — **edge-wan** | `{service}.{domain}` — **backend-lan** | `{service}.local` |
|------|--------------------------------------|-----------------------------------------|-------------------|
| **Internet (WAN)** | ✅ via router `:443` → Caddy | ❌ resolves to a private IP → not routable | ❌ multicast never leaves the LAN |
| **LAN** | ✅ | ✅ | ✅ |
| **WireGuard client** | ✅ | ✅ (routed at L3) | ❌ mDNS is L2 multicast, does not traverse WireGuard |
| **Valid TLS certificate** | ✅ wildcard from Let's Encrypt | ✅ same wildcard | ❌ no public CA → HTTP or `tls internal` |
| **Passkeys / WebAuthn** | ✅ | ✅ | ❌ no Secure Context without valid HTTPS |

`.local` is a convenience path for the LAN. Anything that needs passkey login must
use `{service}.{domain}`.

---

## 2. Inbound — outside vs. inside, and the three paths

Three independent ways a service gets reached. Colour code:
**red = path ① WAN**, **blue = path ② LAN via domain**, **green = path ③ mDNS**.

```mermaid
flowchart TB
    subgraph OUT["🌐 OUTSIDE — Internet / WAN"]
        WANC(["Internet client"])
        CF["Cloudflare DNS<br/>public zone · grey cloud"]
        DEAD(["⛔ private IP<br/>not routable from WAN"])
    end

    ROUTER["🔒 Router<br/>only port 443 forwarded"]

    subgraph IN["🏠 INSIDE — LAN / WireGuard"]
        LANC(["LAN client"])
        WGC(["WireGuard client"])
        MDNS["mDNS / Avahi<br/>*.local · LAN only"]
        CADDY["Caddy ingress<br/>:80 / :443"]

        subgraph SVC["Services — bind 127.0.0.1 only"]
            EDGE["Edge / WAN-exposed<br/>jellyfin · jellyseerr<br/>audiobookshelf · navidrome"]
            BACK["Backend / internal only<br/>sonarr · radarr · readarr<br/>lidarr · prowlarr · sabnzbd"]
            NONE["no vHost<br/>recyclarr · exportarr"]
        end
    end

    WANC -->|"① service.domain"| CF
    CF -->|"① A record → WAN IP<br/>edge services only"| ROUTER
    ROUTER --> CADDY

    LANC -->|"② service.domain"| CF
    WGC -->|"② service.domain"| CF
    CF -->|"② wildcard * → LAN IP<br/>dynamic, all non-edge"| CADDY

    LANC -->|"③ service.local"| MDNS
    MDNS -->|"③ → LAN IP<br/>all UI services"| CADDY

    CADDY --> EDGE
    CADDY --> BACK
    CADDY -.->|"never exposed"| NONE
    CF -.->|"backend name from Internet"| DEAD

    classDef cloudflare fill:#F38020,stroke:#8a4a10,color:#ffffff,stroke-width:2px
    classDef svc fill:#e8eefc,stroke:#2c5aa0,color:#000
    classDef dead fill:#eeeeee,stroke:#999999,color:#666666
    class CF cloudflare
    class EDGE,BACK,NONE svc
    class DEAD dead
    style OUT fill:#fff5f5,stroke:#c0392b,stroke-width:2px
    style IN fill:#f2fbf2,stroke:#27ae60,stroke-width:2px
    style SVC fill:#ffffff,stroke:#2c5aa0,stroke-dasharray:4 3

    linkStyle 0,1,2 stroke:#c0392b,stroke-width:2px
    linkStyle 3,4,5 stroke:#2c5aa0,stroke-width:2px
    linkStyle 6,7 stroke:#27ae60,stroke-width:2px
```

### The three paths

| # | Path | DNS target | Covers | Used from |
|---|------|-----------|--------|-----------|
| **①** | DDNS → **router / external IP** | explicit A record → WAN IP | **only WAN-exposed** (edge) services | Internet |
| **②** | DDNS → **internal IP** | wildcard `*` + `@` → LAN IP, dynamic | all services **without** an explicit WAN record | LAN, WireGuard |
| **③** | **mDNS** → internal IP | `{service}.local` | **all** enabled UI services | LAN only |

**Important nuance on ② — it does *not* cover every service.** In DNS, a specific
record beats a wildcard. Because the edge services own an explicit A record
pointing at the WAN IP, they resolve to the **WAN IP even from inside the LAN**.
Reaching them from home therefore depends on the router supporting **hairpin NAT**
(NAT loopback). The path that really covers *all* services from the LAN is ③ (`.local`).
If hairpin NAT is unavailable, the options are split-horizon DNS or simply using
`.local` internally.

**Further key points**

- Only **two** anchors are maintained dynamically: edge names follow the **WAN IP**
  (router DDNS), the wildcard follows the **current LAN IP** (`ddclient` via
  `ip route get 1.1.1.1` — works on 192.168, 172.16 and 10.0 alike).
- Backend names deliberately resolve to a **private IP**; from the Internet the
  connection dies at routing. That is the intended protection, not a bug.
- Edge names stay **unproxied / grey cloud** (streaming ToS).
- WireGuard clients use ② but **never** ③ — multicast does not traverse an L3 tunnel.

---

## 3. Outbound — egress and VPN confinement

```mermaid
flowchart LR
    SAB["sabnzbd"]
    PRO["prowlarr"]
    ARR["sonarr, radarr,<br/>readarr, lidarr"]
    MED["jellyfin, navidrome,<br/>audiobookshelf"]

    WG["WireGuard 'privado'<br/>RestrictNetworkInterfaces = lo, privado<br/>plus UID policy routing"]
    BLOCK(["uplink blocked<br/>by eBPF filter"])
    INET["Internet"]

    SAB --> WG
    PRO --> WG
    SAB -.->|"blocked"| BLOCK
    PRO -.->|"blocked"| BLOCK
    WG --> INET

    ARR -->|"direct, TRaSH: no VPN"| INET
    MED -->|"direct, metadata"| INET
```

**Key points**

- The downloaders can physically only open sockets on `lo` and the VPN interface.
  Even if the VPN routing table disappears, they cannot fall back to the uplink —
  that is the kill switch.
- The `*arr` services intentionally run **without** VPN: metadata providers block
  known VPN ranges (TRaSH guidelines).
- DNS for the confined services is pinned via a bind-mounted `resolv.conf`.

---

## 4. TLS — certificates without opening a port

```mermaid
flowchart LR
    ACME["security.acme / lego"]
    CFAPI["Cloudflare DNS API<br/>_acme-challenge TXT"]
    LE["Let's Encrypt"]
    CERT["wildcard cert *.domain<br/>/var/lib/acme"]
    CADDY["Caddy<br/>useACMEHost"]

    ACME -->|"DNS-01 challenge"| CFAPI
    CFAPI -->|"verify"| LE
    LE -->|"issue"| CERT
    CERT -->|"read, group caddy"| CADDY
```

**Key points**

- **DNS-01** proves domain ownership through a TXT record, so the host never has to
  be publicly reachable. This is why LAN-only services still get a valid certificate.
- One wildcard `*.{domain}` covers every service. The apex `{domain}` needs to be
  listed separately — a wildcard does not cover it.
- Certificates are issued by lego, not by Caddy (separation of concerns).

---

## 5. Common traps

| Trap | Why it hurts |
|------|--------------|
| `.local` in Cloudflare | `.local` is multicast-only; a unicast record collides with mDNS |
| Expecting `.local` to work over WireGuard | multicast is L2, WireGuard is L3 |
| Passkey login on `.local` | no valid certificate → no Secure Context → WebAuthn refuses |
| Orange cloud on streaming edge | Cloudflare ToS, and it breaks streaming |
| Hardcoding a LAN IP or NIC name | breaks on a new router, subnet or machine |
| Opening service ports in the firewall | bypasses Caddy and its auth entirely |
