# packages — eigene Paketdefinitionen

## Erst suchen, dann paketieren

Bevor hier irgendetwas entsteht, der Pflichtablauf aus
`.claude/rules/nix-recherche.md` — inklusive Namensvarianten (`-web`, `-server`,
`-cli`, `-unwrapped`) und einem Blick in den **Paketinhalt**.

Bei Feishin wurde dreimal behauptet, es muesse paketiert werden. `feishin-web`
lag die ganze Zeit fertig in nixpkgs.

## Wenn doch paketiert wird

- `meta.description`, `meta.license`, `meta.homepage` setzen — sonst ist das
  Paket fuer den naechsten Leser eine Blackbox
- Quell-URL als Kommentar, damit die Version nachvollziehbar bleibt
- Kein `fetchurl` mit geratenem Hash. Bauen lassen, echten Hash uebernehmen

## Upstream schlaegt lokal

Sobald ein Paket in nixpkgs landet, fliegt die lokale Definition raus. Eine
eigene Definition ist Wartungslast, kein Besitz.
