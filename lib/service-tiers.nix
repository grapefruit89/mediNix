# ---
# id: "service-tiers"
# domain: "50"
# status: "active"
# layer: 5
# role: lib
# purpose: "SSoT DNS-Tier-Zuordnung je Media-Service (edge-wan / backend-lan / none)"
# tags: [lib, dns, tiers, cloudflare, ingress]
# docs:
#   - modules/50-media/grok-review.md
# ---
#
# Kanonische, FESTE Tier-Tabelle (grok-review.md P0-4 / Abschnitt 0.2).
# Bewusst KEINE per-Service mkOptions: solange kein Konsument (Host-DDNS,
# Cloudflare, Assertions) die Tiers wirklich liest, waere eine Options-API
# reines Over-Engineering. Overrides kommen erst in Phase C, wenn der
# CF-/DDNS-Export sie tatsaechlich auswertet.
#
# Tier-Bedeutung:
#   edge-wan    -> darf aus dem WAN erreichbar sein. CNAME -> CF-Anker 2
#                  (Router/WAN-IP, unproxied/grau -- Streaming-ToS).
#   backend-lan -> nur LAN-DNS. CNAME -> CF-Anker 3 (LAN-IP des Media-Hosts,
#                  unproxied). Aus dem Internet: Private-IP -> tot (gewollt).
#   none        -> kein vHost, kein CF-Name (Metrics/Generatoren/CLI-only).
#
# Regeln (grok-review.md Fallstrick): NIEMALS .local in Cloudflare, NIEMALS
# starre Heim-IP im Modul. Diese Datei liefert nur Namen + Tier; IPs/DDNS
# macht der Host (10-network).
{ lib }:
let
  # Primaerquelle: Service -> Tier.
  byService = {
    jellyfin       = "edge-wan";
    jellyseerr     = "edge-wan";
    audiobookshelf = "edge-wan";
    navidrome      = "edge-wan";

    sonarr         = "backend-lan";
    radarr         = "backend-lan";
    readarr        = "backend-lan";
    lidarr         = "backend-lan";
    prowlarr       = "backend-lan";
    sabnzbd        = "backend-lan";

    recyclarr      = "none";
    exportarr      = "none";
  };

  servicesInTier =
    tier: lib.attrNames (lib.filterAttrs (_: t: t == tier) byService);
in
{
  inherit byService;

  # Abgeleitete Listen fuer Doku, Assertions und den spaeteren CF/DDNS-Export.
  edgeServices    = servicesInTier "edge-wan";
  backendServices = servicesInTier "backend-lan";
  noneServices    = servicesInTier "none";

  # Lookup mit sicherem Default fuer Services, die (noch) nicht in der Map
  # stehen -- z.B. spaetere UIs vor ihrer bewussten Einordnung.
  tierOf = name: byService.${name} or "none";
}
