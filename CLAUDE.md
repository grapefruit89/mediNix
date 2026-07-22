@AGENTS.md

# CLAUDE.md — Betriebsanweisung für Claude Code auf q958

> ## ⚖ ERSTES GEBOT — der Dezimalrahmen
> Vier feste Anker regieren Ordner und Nummern **jedes** Projekts, auf jeder Ebene:
> **`_0` Fundament · `_1` Zugang · `_2` Sicherheit · `_9` Leitplanken** — dazwischen
> (`_3`–`_8`) die freie, projekteigene Mitte. Port = Nummer × 10, UID = Nummer×10, GID = Projekt×1000.
> **Volle Autorität und Begründung: `devNIX/50-core/adr/8000-dezimalrahmen.md`.**
> Geht das verloren, verliert das Projekt die Orientierung. Niemals löschen.

`AGENTS.md` darüber ist die Verfassung: sie gilt für jeden Agenten und ändert
sich selten. Diese Datei ist der Arbeitsauftrag für **dich, hier, auf dieser
Maschine**.

---

## Du führst aus. Du fragst nicht, ob der Mensch ausführen soll.

Du läufst auf q958. Nix ist da, systemd ist da, das Repo ist da, `sudo` braucht
kein Passwort. **Führe die Befehle in diesem Dokument selbst aus.** Bitte den
Menschen nicht darum, sie für dich zu tippen.

Das ist keine Höflichkeitsfloskel, sondern eine wiederholte Beschwerde des
Repo-Eigentümers: *„eigentlich sollst du die Arbeit erledigen, also KI/LLM
Agents, und nicht ich."* Wer eine Prüfung als Vorschlag formuliert, statt sie
durchzuführen, hat die Aufgabe nicht erledigt.

**Drei Ausnahmen — hier wird gefragt, nie eigenmächtig gehandelt:**

1. `git push` — nur nach ausdrücklicher Zustimmung im Chat
2. Schreiben im Repo **Nix-Grok** — verboten, es ist stillgelegt
3. Löschen von `/data/media` oder `/etc/nixos` — alles andere darf gewischt werden

---

## Pflichtlauf zu Sitzungsbeginn

Vor der ersten Aussage über den Systemzustand. Nicht aus dem Gedächtnis, nicht
aus einer Zusammenfassung einer früheren Sitzung.

```bash
cd ~/mediNix && git log --oneline -5 && git status --short
systemctl --failed --no-pager
for s in jellyfin sonarr radarr readarr lidarr prowlarr sabnzbd navidrome \
         jellyseerr audiobookshelf feishin; do
  printf "%-16s %s\n" "$s" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$s.local)"
done
[ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ] \
  && echo "bootfest" || echo "NICHT bootfest -- switch fällig"
```

Widerspricht eine erinnerte Zusammenfassung dem, was diese Befehle zeigen,
**haben die Befehle recht**. Sag das dem Menschen, bevor du weitermachst.

---

## Recherche ist Arbeitsschritt null, nicht Kür

> *„Nix-Recherchewerkzeuge sind ein grundlegender Arbeitsschritt, ohne den wir
> garnicht erst eine Zeile Code schreiben sollten."*

| Frage | Werkzeug |
|---|---|
| Paketname, `services.*`-Option existiert? | **nixos-MCP** `{"action":"info"/"search"}` |
| `lib.*` / `builtins.*`, Argumentreihenfolge | **Noogle** `{"source":"noogle"}` |
| Caddy, systemd, Jellyfin-API, externe Libs | **Context7** |
| Fehler aus einem Fremdpaket | **GitHub-MCP** — Issues, bevor du debuggst |
| Was ist auf q958 **wirklich** evaluiert? | `nix eval /etc/nixos#nixosConfigurations.q958.config.<attr>` |

**Der Ablauf steht in `.claude/rules/nix-recherche.md`** und ist Pflicht, bevor
du behauptest, etwas gebe es nicht. Ein negatives Ergebnis aus einem untauglichen
Befehl ist kein Ergebnis.

---

## Änderung → Nachweis. Immer in dieser Reihenfolge.

```bash
# 1. committen, BEVOR die Werkzeuge laufen
git add -A && git commit -m "..."

# 2. Werkzeuge
NIXFILES=$(find . -name '*.nix' -not -path './.git/*')
nix run nixpkgs#nixfmt -- $NIXFILES
nix run nixpkgs#nixf-diagnose -- --ignore=sema-unused-def-lambda-noarg-formal $NIXFILES
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .

# 3. committen, WAS die Werkzeuge geändert haben
git add -A && git commit -m "nixfmt/statix/deadnix"

# 4. Diff prüfen — der eigentliche Zweck der Trennung
git show --stat HEAD && git show HEAD

# 5. push NUR nach Zustimmung im Chat
```

Diese Trennung stammt vom Repo-Eigentümer und hat sich sofort bewährt:
`deadnix --edit` machte aus `{ lib }:` ein `{ }:` und zerlegte alle Aufrufer.
In einem gemeinsamen Commit wäre das untergegangen.

**Aktivieren:**

```bash
sudo nix flake update mediNix --flake /etc/nixos
setsid nohup sudo nixos-rebuild switch --flake /etc/nixos#q958 > /tmp/sw.log 2>&1 &
```

`setsid nohup`, nicht `systemd-run` — Begründung in `.claude/rules/betrieb.md`.

---

## Behauptungen brauchen einen Gegentest

Ein Dienst, der läuft, beweist nicht, dass deine Änderung ihn zum Laufen gebracht
hat. Nimm die Bedingung weg und sieh nach, ob es bricht.

| Was du zeigen willst | Wie du es zeigst |
|---|---|
| „Änderung ist rein kosmetisch" | Store-Pfad vorher/nachher vergleichen — bitgleich |
| „Diese Zeile war die Ursache" | Zeile entfernen, Fehler muss zurückkommen |
| „Der Dienst ist erreichbar" | `curl` **von außen** über `.local`, nicht `127.0.0.1` |
| „Der Dienst läuft" | `is-active` **und** `NRestarts` **und** der Port |

Warum der letzte Punkt: Jellyfin war `active` mit 0 Neustarts — und lauschte auf
dem falschen Port, weil die Vorgaben nie griffen. Caddy lieferte 502. Ein
laufender Dienst kann unerreichbar sein.

---

## Erledigt sieht so aus

Ein Lauf ist fertig, wenn du das ausgeben kannst — mit echten Zahlen:

```
┌─ mediNix ────────────────────────────────────────────┐
│  Dienste       11/11 antworten                       │
│  Units         0 failed                              │
│  Lint          nixfmt · statix · deadnix  sauber     │
│  eval          .#nixosConfigurations.check  ok       │
│  System        bootfest                              │
│  Git           <sha>  main  clean                    │
│  Offen         <was nicht geht, oder "nichts">       │
└──────────────────────────────────────────────────────┘
```

Eine ehrlich markierte Lücke ist brauchbar. Eine unmarkierte Vermutung ist
gefährlich.

---

## Was schon schiefging — nicht wiederholen

Vollständig in `LEARNINGS.md` (L1–L7). Die teuersten:

| | |
|---|---|
| **Dreimal falsch geurteilt** über ein Paket, ohne den Store-Inhalt anzusehen | Erst `nix build` + `find`, dann behaupten |
| **Downgrade als Fix vermutet**, ohne die Vermutung zu prüfen | Der Fehler lag in unserem `preStart`, nicht in der Version |
| **`systemd-run`** zum Abkoppeln des Rebuilds | Minimaler PATH, scheitert mit `[Errno 2] ... 'test'` |
| **Ein Marker, den der Dienst nicht mehr anlegt** | `data/jellyfin.db` statt `config/migrations.xml` |

> Wenn eine Prüfung nichts findet, ist die erste Frage nicht *„gibt es das
> nicht?"*, sondern **„habe ich richtig gesucht?"**

---

## Wo was liegt

| | |
|---|---|
| Verfassung, gilt für alle Agenten | `AGENTS.md` |
| Ordner-Regeln, laden nach Pfad | `.claude/rules/*.md` |
| Regeln zu **einem** Modul | `CLAUDE.md` im jeweiligen Ordner |
| Zugangswege, Ports, Fallen dieser Maschine | `CLAUDE.local.md` (gitignored) |
| Was wir schmerzhaft gelernt haben | `LEARNINGS.md` |
| Neue Maschine, von null bis läuft | `50-core/ONBOARDING.md` |
| Wie die Teile zusammenhängen | `50-core/ARCHITEKTUR.md` |
| Etwas ist kaputt — Fehler, Diagnose, Fix | `50-core/RUNBOOK.md` |
| Momentaufnahme, wo wir stehen | `STATUS.md` |
| Entscheidungen mit Begründung | `50-core/adr/` |
| Die eine Wahrheit zu Port, UID, Tier | `lib/registry.nix` |
