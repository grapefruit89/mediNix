# Grok Audit 2 — Arbeitsrahmen, Stand, offene Arbeit

**Datum:** 2026-07-15  
**Autor:** Grok (Audit nach Phase A + Phase B im Working Tree)  
**Gültigkeit:** ab jetzt, bis explizit ersetzt  

Verwandte Dokus (nicht ersetzen, nur ergänzen):

| Datei | Rolle |
|-------|--------|
| `grok-review.md` | Architektur-SSoT Naming/DNS/Ingress/Tiers/Fallstrick |
| `grok-audit-2.md` | **dieser File** — Prozess, Fokus, erledigt, offen |
| `README.md` | Nutzer-Doku (kann hinter Code liegen) |
| `handoff-v2.md` / `claude-review*.md` | historisch; DNS-Abschnitte teils überholt |

---

## 1. Verbindlicher Arbeitsrahmen (Mo, 2026-07-15)

### 1.1 Fokus-Repo: **mediNix** (klein, Standalone)

| | |
|--|--|
| **Repo** | [github.com/grapefruit89/mediNix](https://github.com/grapefruit89/mediNix) |
| **Rolle** | **Kanonische** Quelle für den portablen Media-Stack (`grapefruitMedia`) |
| **Zweck** | Eigenständiges NixOS-Media-Modul / Flake — **Hauptgrund** für die NixOS-Media-Arbeit in dieser Phase |
| **Nicht-Fokus** | Großes Monorepo **Nix-Grok** (Maschinen, 10-network, 20-security, q958, …) |

**Entscheidung:**

> Wir kümmern uns **zuerst und vorrangig** um das **kleine Media-Repo (mediNix)**.  
> Nix-Grok-Monorepo-Spiegelung, q958-Host-Ingress, Cloudflare-Live-DDNS am Router — **später / andere Baustelle**.

### 1.2 Kein Server, nur Code

| | |
|--|--|
| **Server (q958 o. Ä.)** | **Aktuell nicht verfügbar** — kein Dry-Build, kein Live-Deploy-Gate |
| **Arbeitsmodus** | **Nur Code + Doku** (Architektur, Module, README, Reviews) |
| **Eval/rebuild** | Wenn wieder ein NixOS-Host da ist — nicht blockierend für Fortschritt |

Konsequenz: Fortschritt wird an **Vollständigkeit des Modul-Codes und der Doku** gemessen, nicht an „läuft auf der Box“.

### 1.3 Zwei Repos — was das bedeutet (kurz)

| Ort | Jetzt |
|-----|--------|
| **mediNix** | Soll die gepushte Wahrheit für den Media-Stack sein |
| **Nix-Grok `modules/50-media`** | Oft Working-Tree / Antigravity-Kopie; kann vorlaufen oder nachhinken |

**Regel:** Features und Fixes **für Media** zielen auf **mediNix**. Monorepo-Sync ist optional und **nicht** Voraussetzung, um weiterzubauen.

---

## 2. Fallstrick (unverändert, Pflicht)

```
.local     = NUR Multicast (mDNS) im LAN — NIEMALS Cloudflare, NIEMALS Unicast-Rewrite
*.domain   = Unicast (optional); öffentlich nur Edge; Backend-DNS → LAN-Anker (später CF)
```

Details: `grok-review.md` (dicker Fallstrick-Block).

---

## 3. Was bereits umgesetzt ist

### 3.1 Frühere Wellen (mediNix-History / Tree)

| Thema | Kurz |
|-------|------|
| Portables Modul `grapefruitMedia.*` | Options, Storage, Ports, Secrets-Pfade, VPN-Interface-Name |
| Loopback-Bind, keine pauschale Firewall-Öffnung (K3) | Dienste hinter Ingress |
| Auth Forms/External + Warnings | `authProxyPresent` |
| Per-Service API-Keys + Generator (K4) | `…__AUTH__APIKEY`, idempotent |
| Ingress Bug1–4 | enabledServices, forward_auth, skipPaths, tls custom :443 |
| Factory-Hygiene, media-Gruppe zentral | M2/M4/M9 |
| Phase 0 Cleanup | tote Prototypen/Optionen raus |
| compat-my.nix | nur für Nix-Grok/q958 — **nicht** mediNix-Kernpflicht |

### 3.2 Phase A light + Quick-Wins (u. a. mediNix `0bd1269`)

| ID | Was |
|----|-----|
| **P1-6** | `caddy run --adapter caddyfile` |
| **P2-3** | `*arr` EnvironmentFile mit `-`-Prefix |
| **P0-1** | `domain`: `nullOr str`, default `null`; Guards (Ingress, Jellyfin-URL, Navidrome-OIDC) |
| **P0-4** | `lib/service-tiers.nix` — feste Map edge-wan / backend-lan / none (**keine** Options-Zoo) |
| **P0-2** | README DNS-Kanon (mDNS immer, L2 optional, 3-Anker-Konzept) |
| **P3-3** | QuickSync-Doku = ABS, nicht Jellyfin |

### 3.3 Phase B (Working Tree; **Push nach mediNix prüfen/nachziehen**)

| ID | Was |
|----|-----|
| **P1-1** | `discovery.mdns` + `500-media-ingress/mdns.nix` — Avahi, `{service}.local` → dynamische LAN-IP |
| **P0-3** | Caddy: immer `{name}.local`, plus `{name}.{domain}` wenn Domain gesetzt |
| **P1-7** | Global: `http://{name}.local` + optional Domain-vHost; Assertion gegen `domain=*.local` |
| Doku | README TLS-Verhalten L1/L2; grok-review Status-Updates |

**Hinweis:** Phase-B-Dateien lagen zuerst im Antigravity/Nix-Grok-Pfad. Für den Fokus-Repo-Stand: **nach mediNix committen/pushen**, sobald der Tree steht.

---

## 4. Was wir noch umsetzen müssen

Priorität im Sinne **mediNix + Code-only** (kein Server, kein Monorepo-Zwang).

### 4.1 P0 / P1 — noch offen im Media-Modul (sinnvolle nächste Code-Schritte)

| Prio | ID | Thema | Warum / Was |
|------|-----|--------|-------------|
| **1** | **Push-Sync** | Phase B (+ ggf. Audit-Dateien) nach **mediNix** | Sonst ist mediNix hinter dem Working Tree |
| **2** | **P2-1** | `vpn.dns` Default nicht still `1.1.1.1` | Default `[]` + Assertion/Warning wenn confinement an und DNS leer |
| **3** | **P2-2** | Warning wenn Usenet-Confinement an, Interface fehlt | Diagnose ohne echten Server-Test trotzdem sinnvoll im Code |
| **4** | **P2-4** | Secrets-Generator nur enabled Services, härter | Standalone-Qualität |
| **5** | **P1-2 Rest** | Assertion/Doku schon teils da; Seeds/URLs prüfen | Edge-Cases ohne Domain |
| **6** | **P1-3 (nur Modul)** | Options/Export der Tier→CNAME-Soll-Liste | **Kein** Cloudflare-Client nötig; nur deklarative SSoT für spätere Hosts |
| **7** | **P1-4** | optional: Assertion Backend nicht als edge | Defense in depth, Code-only |
| **8** | **P2-9** | Security-Baseline-Checkliste + optionale `assertions.strict` | Standalone-Härtung dokumentiert erzwingen |
| **9** | **P2-5** | arr-provision (Indexer, Download-Clients, Key-Sync) | Größter **Funktions**-Rest vs. Original; eigener Meilenstein |
| **10** | **P2-6** | Exportarr-Scrape-Hooks / VPN OnFailure-Hook (Optionen) | Observability-Schnittstelle, optional |
| **11** | **P3-1** | Feishin / Libreseerr nativ (edge-wan) | Später; POL: kein Docker |
| **12** | **Doku** | `grok-review.md` + dieses Audit in mediNix ablegen | SSoT mitliefern |

### 4.2 Bewusst **zurückgestellt** (kein Server / nicht mediNix-Kern)

| Thema | Warum warten |
|-------|----------------|
| **P1-9** q958 Host-Ingress lernt `.local` | Kein Server; Host liegt in Nix-Grok `10-network`, nicht mediNix |
| **compat-my.nix** weiter pflegen | Monorepo-Adapter; mediNix-Standalone braucht es nicht zum Laufen |
| **CF-3-Anker live** (DDNS WAN + LAN-IP bei Cloudflare) | Braucht DNS-Konto, oft Host-DDNS (`10-network`); mediNix liefert nur Tiers/Namen |
| **Landingpage Apex proxied** | Host-Sache |
| **Blocky DoT / 5 Upstreams** | Host-DNS; Media rührt `:53` nicht an |
| **Nix-Grok Monorepo CRLF-Renorm + Full-Sync** | Explizit **nicht** Blocker; optional später |
| **Dry-Build / nixos-rebuild** | Kein Server |

### 4.3 Zielbild mediNix „Standalone fertig genug“ (Checkliste)

Code/Doku — **ohne** echten Host:

- [x] Domain nullbar, kein Default `.local`
- [x] Tier-SSoT-Datei
- [x] mDNS `{service}.local` + Caddy L1
- [x] Caddy L2 wenn Domain
- [x] Loopback, Auth-Hooks, per-Service-Keys, Ingress-Basics
- [ ] Phase B auf **mediNix GitHub** sichtbar
- [ ] VPN-DNS-Default sauber (P2-1/2)
- [ ] Generator nur enabled + Baseline-Assertions (P2-4/9)
- [ ] Optional: Tier-Export für CF (P1-3 light)
- [ ] arr-provision als optionales Layer (P2-5) — großer Block
- [ ] README = Single Entry für Fremdnutzer (Quickstart aktuell halten)

---

## 5. Empfohlene Reihenfolge ab hier (nur mediNix / Code)

```text
1. Phase B (+ grok-audit-2, grok-review) nach mediNix pushen
2. Kleine Security-Restfixes: P2-1, P2-2, P2-3 schon da, P2-4
3. P1-3 light: nur deklarative Anker-/CNAME-Soll-Optionen (kein API-Client)
4. P2-9 Baseline-Checkliste
5. P2-5 arr-provision (eigener Meilenstein, kann parallel geplant werden)
6. Später: Feishin/Libreseerr, Observability-Hooks
7. Viel später / anderes Projekt: Server wieder da → Deploy, Host-DNS/CF live, optional Nix-Grok-Sync
```

---

## 6. Was andere Audits/Handoffs **nicht** mehr diktieren

| Alte Aussage | Jetzt |
|--------------|--------|
| Dry-Build ist Merge-Gate | **Nein** — kein Server |
| Zuerst Monorepo eval reparieren | **Nein** — mediNix zuerst |
| q958 Host-Ingress vor mDNS | **Nein** — mDNS im Modul; Host später |
| „Kein `.local` / nimm home.arpa“ | **Obsolet** — mDNS immer `.local` |
| Alles A→F vor arr-provision | **Gelockert** — mediNix-Kern vor Host; Provision eigener Block |

---

## 7. Ein-Satz-Zusammenfassung

> **Wir bauen den portablen Media-Stack als Code im kleinen Repo mediNix, ohne Server und ohne Monorepo-Pflicht; Phase A+B (Naming/mDNS/Ingress-Fundament) sind im Tree weitgehend da und müssen auf mediNix landen; offen sind vor allem Security-Feinschliff, deklaratives CF-Tier-Export, arr-provision und spätere UIs — Host/Cloudflare/q958 warten, bis wieder Hardware da ist.**

---

*Ende grok-audit-2.md*
