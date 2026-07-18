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

## 2. Inbound — name resolution and entry

```mermaid
flowchart TB
    INET["Internet client"]
    LANC["LAN client"]
    WGC["WireGuard client"]

    CF["Cloudflare public DNS<br/>grey cloud, DNS only"]
    MDNS["mDNS / Avahi<br/>service.local multicast"]

    ROUTER["Router<br/>only :443 forwarded"]
    CADDY["Caddy ingress<br/>:80 / :443"]
    DEAD(["private IP<br/>not routable from WAN"])

    EDGE["edge-wan<br/>jellyfin, jellyseerr,<br/>audiobookshelf, navidrome"]
    BACK["backend-lan<br/>sonarr, radarr, readarr,<br/>lidarr, prowlarr, sabnzbd"]
    NONE["none, no vHost<br/>recyclarr, exportarr"]

    INET -->|"service.domain"| CF
    LANC -->|"service.domain"| CF
    WGC -->|"service.domain"| CF
    LANC -->|"service.local"| MDNS

    CF -->|"edge name to WAN IP<br/>router DDNS"| ROUTER
    CF -->|"wildcard to LAN IP<br/>ddclient, dynamic"| CADDY
    CF -.->|"backend name, from Internet"| DEAD
    MDNS -->|"host LAN IP"| CADDY
    ROUTER --> CADDY

    CADDY -->|"reverse_proxy 127.0.0.1"| EDGE
    CADDY -->|"reverse_proxy 127.0.0.1"| BACK
    CADDY -.->|"never exposed"| NONE
```

**Key points**

- Only **two** DNS anchors are maintained dynamically: the edge names follow the
  **WAN IP** (router DDNS), the wildcard `*` plus `@` follow the **current LAN IP**
  (`ddclient` using `ip route get 1.1.1.1`, so any subnet works: 192.168, 172.16, 10.0).
- Backend names deliberately resolve to a **private IP**. From the Internet the
  connection dies at routing — that is the intended protection.
- Edge names stay **unproxied / grey cloud** (streaming ToS).

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
