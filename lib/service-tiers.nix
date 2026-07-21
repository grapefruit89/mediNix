# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Weiterleitung auf lib/registry.nix — Tier-Zuordnung liegt dort
#   tags: [tiers, compat]
# ---
#
# Diese Datei enthaelt keine Daten mehr. Die Tier-Zuordnung stand frueher hier
# UND als Port-Liste in default.nix UND als Namensliste in mdns.nix -- dieselbe
# Information an drei Stellen, jede Abweichung ein stiller Fehler.
#
# Sie bleibt als duenne Weiterleitung bestehen, damit bestehende Importe nicht
# brechen. Neuer Code importiert direkt lib/registry.nix.
{ lib }:
let
  registry = import ./registry.nix { inherit lib; };
in
{
  inherit (registry)
    byService
    edgeServices
    backendServices
    noneServices
    tierOf
    ;
}
