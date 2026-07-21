# 500-media-ingress — Caddy und mDNS

Der Eingang. Alles, was von aussen kommt, kommt hier durch.

## Caddy darf niemals verhungern

Ausdrueckliche Ansage des Eigentuemers: *„caddy darf niemals die Ressourcen
ausgehen, genauso wie dem ganzen systemd-Kram."* Deshalb hier — und nur hier —
die Gegenrichtung zur ueblichen Haertung:

```nix
MemoryMin = "64M";                  # wird nie zurueckgefordert
MemoryLow = "128M";                 # nur unter echtem Druck
ManagedOOMPreference = "avoid";     # systemd-oomd laesst ihn in Ruhe
```

`systemd-oomd` ist ein **zweiter, unabhaengiger Killer**. Er ignoriert
`OOMScoreAdjust` komplett. Wer nur den Score setzt, hat halb geschuetzt.

Faellt Caddy, sind **alle** Dienste unerreichbar, auch wenn jeder einzelne laeuft.
Er ist ein Einzelfehlerpunkt und wird entsprechend behandelt.

## Statische Dienste werden ausgeliefert, nicht geproxt

`registry.staticServices` (derzeit nur Feishin) haben keinen Prozess. Caddy
liefert die Dateien direkt aus:

```
file_server + try_files {path} /index.html
```

`try_files` ist bei einer Single-Page-App **Pflicht**: ohne sie ergibt jeder
Deep-Link 404, weil die Route nur im Browser existiert, nicht im Dateisystem.

## mDNS — der Fehler, der sich als Erfolg tarnt

`publish.addresses` und `publish.userServices` sind **nicht** dasselbe. Fehlt
`userServices = true`, wird **kein einziger** `.local`-Name veroeffentlicht — und
der Dienst meldet trotzdem `exit 0`. Kein Fehler, keine Warnung, nur Stille.

Das war L1 und hat einen halben Tag gekostet. Der Exit-Code prueft heute per
`kill -0`, ob die Prozesse wirklich leben.

## Die Namensliste ist abgeleitet, nicht gepflegt

Aus `registry.uiServices`. Wer hier von Hand einen Namen ergaenzt, hat die
Registry umgangen — genau der Fehler, den ADR-5042 abschaffen sollte.

## Pruefen

```bash
for s in $(nix eval --raw --impure --expr \
  '(import ./lib/registry.nix { lib = (import <nixpkgs> {}).lib; }).uiServices' \
  2>/dev/null | tr -d '[]"'); do
  printf "%-16s %s\n" "$s" "$(curl -s -o /dev/null -w '%{http_code}' http://$s.local)"
done
```

Immer **von aussen** ueber `.local` — `curl 127.0.0.1` prueft weder mDNS noch Caddy.
