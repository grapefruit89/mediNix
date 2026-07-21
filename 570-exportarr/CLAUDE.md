# 570-exportarr — Prometheus-Metriken der *arr

Vier Exporter, Nummern 561–564. **Kein UI, kein Ingress.**

## Kaputt und ungeklaert — nicht als fertig melden

```
exporters.enable = true  ->  weder Units noch Ports
```

Reproduzierbar, Ursache unbekannt. Wer hier anfaengt: das ist der Stand, und er
ist nicht erklaert.

Erste Schritte, die noch niemand gemacht hat:

```bash
nix eval /etc/nixos#nixosConfigurations.q958.config.systemd.services --apply builtins.attrNames \
  | tr ',' '\n' | grep -i export
nix eval .#nixosConfigurations.check.config.systemd.services --apply builtins.attrNames \
  | tr ',' '\n' | grep -i export
```

Zeigt der erste Befehl nichts und der zweite etwas, liegt es an der
Host-Verdrahtung. Zeigen beide nichts, greift die `enable`-Bedingung im Modul nicht.

## Warum jeder Exporter eine eigene Nummer hat

Ein Sammeleintrag mit „Basisport plus Versatz" waere wieder eine Nebenrechnung —
und genau die sollte das Nummernschema abschaffen (ADR-5042).
