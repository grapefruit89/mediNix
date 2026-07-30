#!/usr/bin/env bash
# gen-ports-doc.sh -- erzeugt 50-core/PORTS.md aus lib/registry.nix.
# Einzige Wahrheit ist die Registry; diese Datei nie von Hand pflegen.
set -euo pipefail
cd "$(dirname "$0")/.."
nix eval --impure --json --expr '
  let lib = (import <nixpkgs> { }).lib; r = import ./lib/registry.nix { inherit lib; };
  in { gid = r.mediaGid; services = lib.mapAttrs (_: s: { inherit (s) number ui tier; }) r.services; }
' > /tmp/registry.json
python3 <<'PY'
import json
d = json.load(open("/tmp/registry.json")); gid = d["gid"]
rows = sorted(d["services"].items(), key=lambda kv: kv[1]["number"])
o = ["# Ports & IDs \u2014 generiert aus lib/registry.nix\n",
     "> **AUTOGENERIERT** via `scripts/gen-ports-doc.sh` \u2014 nicht von Hand bearbeiten.",
     f"> Formel: Port = UID = Nummer \u00d7 10 \u00b7 GID = {gid} (geteilt).\n",
     "| Nr | Dienst | Port | UID | GID | UI | Tier |", "|---|---|---|---|---|---|---|"]
for name, s in rows:
    n = s["number"]
    o.append(f"| {n} | {name} | {n*10} | {n*10} | {gid} | {'ja' if s['ui'] else 'nein'} | {s['tier']} |")
open("50-core/PORTS.md", "w").write("\n".join(o) + "\n")
print(f"50-core/PORTS.md erzeugt ({len(rows)} Dienste)")
PY
