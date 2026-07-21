# scripts — Helfer

## Nur stdlib, keine externen Abhaengigkeiten

Ein Skript, das `jq`, `yq` oder ein Python-Paket braucht, macht mediNix von
etwas abhaengig, das der Betreiber nicht installiert hat. **Surgical Glue** heisst
duenn und voraussetzungslos.

## Modus, nicht Automatik

Jedes Skript, das etwas veraendert, bekommt `check` und `apply` getrennt.
`check` aendert nichts und sagt, was passieren wuerde. Vorbild:
`disko-prune-deprecated.sh check | apply`.

## Fallen, die hier Zeit gekostet haben

| Falle | Merksatz |
|---|---|
| `pgrep -f name` findet **sich selbst** | `ps ... \| grep -v grep` |
| `/usr/bin/env` existiert auf NixOS nicht | `bash skript.sh`, kein Shebang darauf bauen |
| `git checkout <datei>` holt aus dem **Index** | `git checkout HEAD -- <datei>` |
| Hartkodiertes `ROOT="/etc/nixos"` | Pfad als Argument, nicht als Konstante |

Betriebsregeln zu Rebuild und Switch: `.claude/rules/betrieb.md`.
