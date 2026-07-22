---
titel: "Runbook — Fehler, Diagnose, Behebung"
stand: "2026-07-21"
zielgruppe: "Agenten"
---

# Runbook

Jeder Abschnitt hat ein `error_pattern`. Ein Agent nimmt die Fehlerzeile aus
`journalctl` und sucht damit den passenden Abschnitt:

```bash
journalctl -u <dienst> -n 50 --no-pager | grep -iE "$(grep -oP '(?<=^error_pattern: ").*(?=")' docs/RUNBOOK.md | paste -sd'|')"
```

Alle Einträge hier sind **real passiert**. Keine erfundenen Fälle.

---

## 0. Immer zuerst — die Lage

Vor jeder Diagnose. Nicht aus dem Gedächtnis, nicht aus einer Zusammenfassung.

```bash
cd ~/mediNix && git log --oneline -3 && git status --short
systemctl --failed --no-pager
for s in jellyfin sonarr radarr readarr lidarr prowlarr sabnzbd navidrome \
         jellyseerr audiobookshelf feishin; do
  printf "%-16s %s\n" "$s" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$s.local)"
done
[ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ] \
  && echo "bootfest" || echo "NICHT bootfest"
```

**Erwartete Antworten** — Abweichung davon ist der eigentliche Befund:

| Dienst | erwartet | warum nicht 200 |
|---|---|---|
| jellyfin, sonarr, radarr, readarr, lidarr, prowlarr, navidrome | `302` | leiten auf Login um |
| sabnzbd | `303` | eigene Weiterleitung |
| jellyseerr | `307` | temporäre Weiterleitung |
| audiobookshelf, feishin | `200` | liefern ihre SPA direkt |

> **Ein laufender Dienst kann unerreichbar sein.** `is-active` allein beweist
> nichts. Immer `NRestarts` **und** den Port **und** `curl` von außen.

---

## 1. Dienst startet endlos neu, Datenbank-Fehler

```yaml
error_pattern: "no such table|__EFMigrationsHistory|ActivityLog|SQLite Error 1"
```

**Symptom**

```
SQLite Error 1: 'no such table: ActivityLog'
   at MigrateActivityLogDb.Perform()
jellyfin.service: Scheduled restart job, restart counter is at 44.
```

**Ursache** — nicht die Version. Vorab eingespielte Konfigurationsdateien lassen
den Dienst auf eine **bestehende Installation** schließen; er migriert dann
gegen eine Datenbank, die nie angelegt wurde.

**Was NICHT hilft, bereits erfolglos versucht:**

| Versuch | Ergebnis |
|---|---|
| Downgrade 10.11.11 → 10.10.7 | scheitert identisch, nur an anderer Tabelle |
| `/var/lib/jellyfin` wischen | derselbe Absturz |
| `__EFMigrationsHistory` von Hand anlegen | eine Migration weiter, dann `TypedBaseItems` |

**Behebung** — Vorgaben erst einspielen, wenn die Datenbank existiert:

```bash
if [ ! -f /var/lib/jellyfin/data/jellyfin.db ]; then
  echo "jellyfin: Erststart -- Vorgaben werden uebersprungen"
  exit 0
fi
```

**Prüfen**

```bash
systemctl show jellyfin -p NRestarts --value      # 0
sudo ss -tlnp | grep jellyfin                     # :5410, nicht :8096
```

> **Der Marker muss die Datenbank sein, keine Config-Datei.** Erster Versuch
> prüfte `config/migrations.xml` — die legt 10.11 nicht mehr an. Bedingung nie
> wahr, Vorgaben nie eingespielt, Dienst auf Standardport → Caddy 502.
> Er lief und war trotzdem unerreichbar.

Belege: `LEARNINGS.md` L7, `jellyfin/jellyfin#15158`.

---

## 2. `226/NAMESPACE` — Dienst startet gar nicht erst

```yaml
error_pattern: "226/NAMESPACE|Failed to set up mount namespacing|Failed at step NAMESPACE"
```

**Symptom**

```
jellyfin.service: Failed to set up mount namespacing: /var/cache/jellyfin: No such file or directory
jellyfin.service: Failed at step NAMESPACE spawning ...: No such file or directory
Control process exited, code=exited, status=226/NAMESPACE
```

**Ursache** Ein Pfad steht in `ReadWritePaths`, existiert aber nicht. systemd
scheitert **vor** jeder Codezeile — der Dienst hat nie gestartet.

Typischer Auslöser: jemand hat das State-Verzeichnis gewischt und danach
`nixos-rebuild test` statt `switch` gefahren. `test` legt `tmpfiles` nicht
zuverlässig neu an.

**Behebung**

```bash
sudo systemd-tmpfiles --create
sudo install -d -o <dienst> -g <dienst> -m 0700 /var/lib/<dienst> /var/cache/<dienst>
setsid nohup sudo nixos-rebuild switch --flake /etc/nixos#q958 > /tmp/sw.log 2>&1 &
```

Dauerhaft: eine `systemd.tmpfiles.rules`-Zeile im Modul — **nicht** `install` im
`preStart`, dem fehlt `CAP_CHOWN` (L3).

**Merksatz:** nach jedem Wipe `switch`, nie `test`.

---

## 3. Dienst stirbt wortlos, kein Log

```yaml
error_pattern: "SIGSYS|seccomp|bad system call|signal=SYS"
```

**Symptom** Der Prozess verschwindet. Keine Fehlermeldung, kein Stacktrace,
nichts im Journal außer dem Tod selbst.

**Ursache** `SystemCallFilter` **tötet** per SIGSYS, statt den Aufruf abzulehnen.

**Behebung**

```nix
SystemCallErrorNumber = "EPERM";
```

Danach gibt der Kernel `EPERM` zurück, die Anwendung protokolliert einen
normalen Fehler, und man sieht endlich **welcher** Syscall stört.

> Diese Zeile gehört in **jede** seccomp-Härtung. Ohne sie debuggt man blind.

Beleg: `LEARNINGS.md` L4 (audiobookshelf).

---

## 4. „AppFolder is not writable"

```yaml
error_pattern: "AppFolder .* is not writable|SonarrStartupException|Access to the path .* is denied"
```

**Symptom**

```
SonarrStartupException: AppFolder /var/lib/sonarr is not writable
```

**Ursache** `systemd.tmpfiles` hat das Verzeichnis als `root:root` angelegt,
weil Benutzer und Gruppe nicht explizit gesetzt waren.

**Diagnose und Behebung**

```bash
sudo ls -ld /var/lib/sonarr        # zeigt root root
sudo chown -R sonarr:sonarr /var/lib/sonarr
```

Dauerhaft im Modul, Eigentümer **immer** explizit:

```nix
systemd.tmpfiles.rules = [ "d /var/lib/sonarr 0700 sonarr sonarr -" ];
```

Beleg: `LEARNINGS.md` L2.

---

---

## 4b. Feste UIDs greifen nicht — „not applying UID change"

```yaml
error_pattern: "not applying UID change|not applying GID change|wireFixedUids|feste UID"
```

**Symptom** Nach `grapefruitMedia.wireFixedUids = true` + Switch stehen die
Benutzer weiter auf alten UIDs. Im Switch-Log:

```
warning: not applying UID change of user 'jellyfin' (993 -> 5051)
```

**Ursache** `mutableUsers = true` — NixOS nummeriert **bestehende** Benutzer
nicht um. Die Config ist korrekt (deklariert 5051), aber das laufende System
bleibt auf 993. Die State-Dateien gehören noch der alten UID → Folgefehler
„permission denied" (Abschnitt 4).

**Behebung** Der einmalige Abgleich ist in einem Skript codiert — nicht mehr aus
dem Gedächtnis:

```bash
scripts/migrate-uids.sh check          # zeigt Ist vs. Soll, aendert nichts
sudo scripts/migrate-uids.sh apply     # stoppt, usermod/groupmod, chown, startet
```

`apply` macht genau die Reihenfolge, die am 2026-07-22 von Hand nötig war:
Dienste stoppen → `groupmod media 5000` → `usermod` je Dienst → `chown -R
<neu>:media` über `/var/lib`/`/var/cache` → `/data` auf Gruppe media → starten.

**Nicht nötig bei einer frischen Installation** — dort werden die Benutzer sofort
mit der richtigen UID angelegt. Nur beim Migrieren eines bestehenden Systems.

## 5. `.local` löst nicht auf — und niemand meldet einen Fehler

```yaml
error_pattern: "Name or service not known|could not resolve host|avahi|mdns"
```

**Symptom** `curl http://sonarr.local` scheitert an der Namensauflösung. Der
mDNS-Dienst meldet `exit 0`, `systemctl status` sieht gesund aus.

**Ursache** `publish.addresses` und `publish.userServices` sind **nicht**
dasselbe. Fehlt `userServices`, wird **kein einziger** Name veröffentlicht —
ohne Warnung.

**Diagnose**

```bash
avahi-browse -at | grep -i sonarr
getent hosts sonarr.local
systemctl status avahi-daemon
```

**Behebung**

```nix
services.avahi.publish.userServices = true;
```

Die Namensliste kommt aus `registry.uiServices` — wer hier von Hand ergänzt, hat
die Registry umgangen.

Beleg: `LEARNINGS.md` L1.

---

## 6. Caddy liefert 502, der Dienst läuft aber

```yaml
error_pattern: "502 Bad Gateway|dial tcp .* connection refused|reverse_proxy"
```

**Ursache in aller Regel:** der Dienst lauscht auf einem **anderen Port**, als
die Registry sagt. Seine Portvorgabe hat nicht gegriffen, er fiel auf seinen
Standardport zurück.

**Diagnose**

```bash
sudo ss -tlnp | grep <dienst>                    # tatsächlicher Port
grep -A3 "<dienst> = {" lib/registry.nix         # Nummer × 10 = Sollwert
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<istport>
```

Antwortet der Ist-Port, ist der Dienst gesund und nur falsch verdrahtet.

**Zweite mögliche Ursache:** Caddy selbst ist tot oder wurde vom OOM-Killer
geholt. Dann sind **alle** Dienste weg, nicht nur einer.

```bash
systemctl status caddy
journalctl -u caddy -n 30 --no-pager
```

---

## 7. Statischer Dienst: Startseite geht, Deep-Link 404

```yaml
error_pattern: "404 .*static|try_files|file_server"
```

**Ursache** Single-Page-Anwendung ohne `try_files`. Die Route existiert nur im
Browser, nicht im Dateisystem.

**Behebung**

```
file_server
try_files {path} /index.html
```

Betrifft alle Dienste mit `static = true` in der Registry (derzeit Feishin).

---

## 8. Ein Dienst ist tot und reißt alles mit — Speicherdruck

```yaml
error_pattern: "oom-kill|Out of memory|Killed process|systemd-oomd"
```

**Diagnose**

```bash
journalctl -k --no-pager | grep -i "killed process" | tail -5
systemctl status systemd-oomd
systemctl show caddy -p MemoryMin -p MemoryLow -p ManagedOOMPreference
```

**Ursache, die am häufigsten übersehen wird:** `systemd-oomd` ist ein
**zweiter, unabhängiger Killer**. Er ignoriert `OOMScoreAdjust` vollständig.
Wer nur den Score setzt, hat halb geschützt.

**Behebung für alles, was nicht sterben darf**

```nix
MemoryMin = "64M";
MemoryLow = "128M";
ManagedOOMPreference = "avoid";
```

Die Rangfolge steht in `lib/memory-policy.nix`. Caddy steht ganz oben, weil sein
Ausfall alle Dienste unerreichbar macht, auch die gesunden.

---

## 9. Switch scheitert an kollidierenden Optionen

```yaml
error_pattern: "conflicting definitions|has conflicting definition|mkForce value|The option .* has conflicting"
```

**Symptom**

```
The option `environment.shellAliases.ll' has conflicting definitions:
  - In `.../820-shell': "eza --icons --git -la"
  - In `.../shells-environment.nix': "ls -l"
Use `lib.mkForce value` or `lib.mkDefault value` to change the priority.
```

**Ursache** Zwei Module setzen dasselbe Attribut bei **gleicher Priorität**.
Das Modulsystem ist reihenfolgeunabhängig — es gibt kein „letzter gewinnt".

**Behebung, Prioritäten von stark nach schwach:**

| Aufruf | Priorität | wann |
|---|---|---|
| `mkForce` | 50 | erzwingen, letzte Wahl |
| normale Zuweisung | 100 | Festlegung des Betreibers |
| `mkOverride 900` | 900 | Distributionsvorgabe korrigieren |
| `mkDefault` | 1000 | Vorschlag, jeder darf übersteuern |

Zwei `mkDefault` kollidieren. Wer eine nixpkgs-Vorgabe überschreiben will, aber
den Betreiber gewinnen lassen soll, nimmt **`mkOverride 900`**.

---

## 10. Switch meldet Erfolg, hat aber nichts getan

```yaml
error_pattern: "Errno 2.*'test'|No such file or directory: 'test'|systemd-run.*nixos-rebuild"
```

**Symptom** Kein Fehler in der Ausgabe, aber die Änderung ist nicht aktiv. Im
Unit-Log steht

```
[Errno 2] No such file or directory: 'test'
```

**Ursache** `systemd-run` gibt der Unit einen minimalen PATH ohne coreutils.
`nixos-rebuild` scheitert darin. Am 2026-07-21 galten dadurch **zwei Switches
als erfolgreich, die gescheitert waren** — es fiel erst Runden später auf.

**Behebung**

```bash
setsid nohup sudo nixos-rebuild switch --flake /etc/nixos#q958 > /tmp/sw.log 2>&1 &
```

**Immer gegenprüfen, nie der Ausgabe glauben:**

```bash
tail -3 /tmp/sw.log
[ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ] \
  && echo BOOTFEST || echo "nicht bootfest"
```

Ein Hook in `devnix-agent` blockt diese Kombination inzwischen.

---

## 11. Bekannt offen — keine Fehlersuche nötig

Diese Zustände sind **Absicht** oder ungeklärt. Wer sie „repariert", arbeitet an
einem Phantom.

| Was | Zustand | Grund |
|---|---|---|
| `sabnzbd` lädt nichts | Platzhalter-Zugangsdaten | Secrets gehören nicht ins Repo, Mensch trägt sie im Webinterface ein |
| `usenet-confinement` inaktiv | kein WireGuard-Schlüssel | dito |
| `provision` inaktiv | keine API-Schlüssel | dito |
| `recyclarr` aus | `trash_ids` ungeprüft | falsche IDs zerlegen still die Qualitätsprofile |
| `exporters.enable = true` wirkungslos | **ungeklärt** | erzeugt weder Units noch Ports, Ursache unbekannt |
| `registry.uids`, `mediaGid` | berechnet, nicht verdrahtet | real: UID 274, GID 990 |

---

## 12. Wenn nichts hier passt

1. **Ist es wirklich unser Fehler?** Erst die GitHub-Issues des betroffenen
   Pakets durchsuchen, bevor debuggt wird. Ein offenes Upstream-Issue spart
   30 Minuten.
2. **Habe ich richtig gesucht?** Ein negatives Ergebnis aus einem untauglichen
   Befehl ist kein Ergebnis. Ablauf in `.claude/rules/nix-recherche.md`.
3. **Beweise die Ursache, statt sie zu vermuten.** Bedingung wegnehmen, prüfen
   ob es bricht. Der teuerste Fehler dieses Projekts war eine plausible,
   ungeprüfte Vermutung („es liegt an der Version").
4. **Neuen Fall hier eintragen** — mit `error_pattern`, dem wörtlichen Symptom,
   der widerlegten Erstannahme und dem Gegentest. Ohne die widerlegte Annahme
   dokumentiert der Eintrag nur die Lösung, nicht den Denkfehler.
