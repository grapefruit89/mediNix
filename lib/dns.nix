# ---
# id: "dns-derive"
# domain: "50"
# status: "active"
# layer: 5
# role: lib
# purpose: "Leitet DNS-Namen (edge/backend/vhost) aus Tier-Map + Hostname-Overrides ab"
# tags: [lib, dns, tiers, ddns]
# docs:
#   - modules/50-media/grok-review.md
#   - modules/50-media/docs/network-topology.md
# ---
#
# Reine Ableitungs-Funktion -- kennt KEINE IPs, KEINE feste Domain, KEINEN Provider.
# Quelle der Wahrheit ist lib/service-tiers.nix; hier kommen nur die Namen dazu.
#
# Hostname != Servicename ist ausdruecklich erlaubt (navidrome -> "music",
# jellyseerr -> "seerr"), damit das Modul die Namenskonvention des Hosts abbilden
# kann, ohne sie hart zu kennen.
{
  lib,
  tiers,
  hostnames ? { },
  domain ? null,
  enabledServices ? [ ],
}:
let
  hasDomain = domain != null && domain != "";

  # Override greift, sonst Servicename.
  nameOf = svc: hostnames.${svc} or svc;
  fqdn = svc: "${nameOf svc}.${domain}";

  keep = svc: builtins.elem svc enabledServices;
  edge = lib.filter keep tiers.edgeServices;
  backend = lib.filter keep tiers.backendServices;

  mkPair = svc: lib.nameValuePair svc (fqdn svc);
in
{
  inherit hasDomain;

  # Aktive Dienste je Tier (Servicenamen, nicht FQDNs).
  edgeServices = edge;
  backendServices = backend;

  # FQDNs -- leer wenn keine Domain gesetzt ist (dann existiert nur L1 .local).
  edgeNames = lib.optionals hasDomain (map fqdn edge);
  backendNames = lib.optionals hasDomain (map fqdn backend);

  # service -> FQDN, fuer Ingress-vHosts und Export an den Host.
  vhostMap = lib.optionalAttrs hasDomain (lib.listToAttrs (map mkPair (edge ++ backend)));

  # Einzel-Lookup (auch ohne Domain nutzbar fuer .local-Namen).
  hostnameOf = nameOf;
}
