# checks — die Pruefkonfiguration

Eine minimale Host-Konfiguration, gegen die mediNix evaluiert wird — ohne echte
Hardware, ohne q958.

```bash
nix eval .#nixosConfigurations.check.config.system.build.toplevel.drvPath
```

## Wozu der Store-Pfad taugt

Er ist der **Beweis** fuer „aendert kein Verhalten". Bleibt er ueber eine
Aenderung hinweg bitgleich, war sie rein kosmetisch. Genau so wurden
Tier-Weiterleitung, mDNS-Menge und Auto-Import umgestellt, ohne dass jemand
raten musste.

## Was hier FEHLT — und die wichtigste offene Aufgabe des Repos ist

`checks/` **evaluiert nur**. Es startet nichts, es prueft kein Verhalten. Damit
faellt jeder erreichte Stand still zurueck, sobald ihn jemand bricht.

**Issue #48: `nixosTest`.** Eine VM, die hochfaehrt und behauptet:

```python
machine.wait_for_unit("jellyfin.service")
machine.succeed("test $(systemctl show jellyfin -p NRestarts --value) -eq 0")
machine.wait_for_open_port(5410)          # Registry-Port, nicht 8096
machine.succeed("curl -sf http://localhost:5410 -o /dev/null")
```

Jeder dieser vier Punkte entspricht einem Fehler, der real passiert ist und
manuell wiedergefunden werden musste.

> Ein Schritt gilt erst als gemacht, wenn ein Test fehlschlaegt, sobald man
> dahinter zurueckfaellt. Siehe `.claude/rules/arbeitsweise.md`.
