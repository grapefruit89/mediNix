# 560-recyclarr — Qualitaetsprofile fuer die *arr

Timer ohne Weboberflaeche (`ui = false`, `tier = none`).

## Bewusst NICHT aktiviert

Die `trash_ids` in der Konfiguration sind **ungeprueft**. Recyclarr schreibt
damit direkt in die Qualitaetsprofile von Sonarr und Radarr — falsche IDs
zerlegen still die Profile, und man merkt es erst an merkwuerdigen Downloads.

Vor dem Aktivieren: jede `trash_id` gegen
`https://github.com/TRaSH-Guides/Guides` verifizieren. Nicht gegen das
Gedaechtnis, nicht gegen ein Blogposting.

## Es gibt ein NixOS-Modul

`services.recyclarr.*` existiert in nixpkgs. **Vor** dem Bau eigener Units
pruefen, ob es reicht — Nix-Native first.

```bash
nix eval --raw nixpkgs#recyclarr.version
```
