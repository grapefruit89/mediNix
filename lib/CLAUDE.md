# lib — die geteilten Bausteine

Was hier steht, gilt fuer **alle** Module. Aenderungen wirken ueberall — hier ist
der Store-Pfad-Vergleich besonders wichtig.

## registry.nix — die eine Wahrheit

Ersetzt fuenf frueher handgepflegte Stellen. Ein neuer Dienst = **eine Zeile hier
plus sein Ordner.** Wer daneben einen Port, eine Tier-Zuordnung oder einen
mDNS-Namen von Hand pflegt, hat die Registry umgangen.

```
Port = number x 10        UID = 5000 + Rest        GID = fix 5000
```

Die GID ist die **bewusste** Ausnahme: waere sie isomorph, bekaeme jeder Dienst
seine eigene Gruppe, und der gemeinsame Bibliothekszugriff braeche.

> **Ehrlicher Stand:** `uids` und `mediaGid` sind über 590-leitplanken **verdrahtet** (bei
> `wireFixedUids = true`). Auf q958 aktiv: Sonarr UID 5320, media-GID 5000. Die Isomorphie ist bei Ports
> umgesetzt, bei UIDs **nicht**.
>
> Beide Felder sind ausführlich in `registry.nix` selbst kommentiert — inklusive
> dessen, was die Verdrahtung kostet (UID-Migration mit `chown -R`, sonst startet
> kein Dienst mehr). **Nicht löschen:** sie tragen die Entscheidung aus ADR-5042.
> Gelöscht wäre das Problem unsichtbar, nicht gelöst.

## service-factory.nix — das Chamaeleon

```nix
harden = if enforce then lib.mkForce else lib.mkDefault;
```

`mkDefault` ist der Normalfall. **Der Host muss uebersteuern koennen**, sonst ist
mediNix nicht portabel (AGENTS.md Regel 3). Frueher standen hier 26x `mkForce`
und 0x `mkDefault` — das machte das Modul zum Diktator auf fremden Systemen.

Ausnahme: `PrivateDevices` bleibt `lib.mkForce false`, wenn GPU gewollt ist —
sonst gibt es keine Transkodierung, und ein stiller Default waere hier fatal.

## gpu.nix — mit ehrlicher Grenze

Vendor-Abstraktion (`intel`/`amd`/`nvidia`/`none`). **Nix kann keine Hardware
abfragen** — `detect` liest die Host-Konfiguration, nicht das Geraet. Das steht
so im Kopf der Datei und darf nicht wegoptimiert werden.

## assertions.nix — die Grenze ist hart

- **Erlaubt:** unsere eigenen Optionen pruefen
- **Verboten:** die Umgebung des Betreibers beurteilen („Es laeuft kein Authelia")

mediNix sichert seinen eigenen Ordner ab, nicht den Server des Nutzers.

## memory-policy.nix — die Leiter

```
caddy-media 400 · postgres/pocketId 300 · jellyfin 250
audiobookshelf/navidrome 200 · arr 100 · sabnzbd 40 · observability 30
```

`CPUWeight` ist relativ und wirkt nur unter Druck — `CPUQuota` deckelt hart und
verschenkt Leistung im Leerlauf. Deshalb Weight.

## Vor jeder Aenderung hier

```bash
nix eval .#nixosConfigurations.check.config.system.build.toplevel.drvPath
```

Vorher und nachher. Gleicher Pfad = kein Verhalten geaendert. Das ist der Beweis,
nicht die Behauptung.
