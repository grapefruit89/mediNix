## aus 551-jellyfin

# 551-jellyfin — Medienserver

Port 5410 (Registry 541 x 10). GPU-Transkodierung ueber `lib/gpu.nix`.

## Vorgaben erst NACH dem ersten Start — das ist die zentrale Regel hier

Jellyfin entscheidet an seinem Migrationsstand, ob eine Installation schon
existiert. Legt man Konfigurationsdateien hin, **bevor** es je lief, schliesst es
auf eine bestehende Installation und migriert gegen eine Datenbank, die es nicht
gibt:

```
SQLite Error 1: 'no such table: ActivityLog'
```

Endlos-Neustart. Der `preStart` bricht deshalb ab, solange
`/var/lib/jellyfin/data/jellyfin.db` fehlt. Die Vorgaben greifen ab dem zweiten Start.

## Zwei Fallen, beide real passiert

**Nicht die Version verdaechtigen.** 10.11.11 und 10.10.7 scheiterten identisch,
nur an verschiedenen Tabellen. Ein Downgrade auf 10.10.7 wurde gepinnt, gebaut,
getestet — und half nicht. Die Ursache lag im eigenen `preStart`.

**Der Marker muss die Datenbank sein, keine Config-Datei.** Erster Versuch pruefte
`config/migrations.xml` — die legt 10.11 nicht mehr an (dort steht `database.xml`).
Bedingung nie wahr, Vorgaben nie eingespielt, Jellyfin auf seinem Standardport
8096 statt 5410, Caddy lieferte 502. **Der Dienst lief und war unerreichbar.**

> Als Marker taugt nur, was der Dienst *zwingend* anlegt — nicht, was er *derzeit*
> anlegt. Config-Dateinamen sind ueber Versionen nicht stabil.

## `/var/cache/jellyfin` muss existieren

Steht in `ReadWritePaths`. Fehlt das Verzeichnis, scheitert schon das
Mount-Namespacing, bevor irgendein Code laeuft:

```
Failed to set up mount namespacing: /var/cache/jellyfin: No such file or directory
status=226/NAMESPACE
```

Angelegt per `systemd.tmpfiles.rules` — nicht per `install` im `preStart`, weil
dem die `CAP_CHOWN` fehlt (das war L3).

## GPU

`PrivateDevices` muss `false` sein, wenn Transkodierung gewollt ist — die Factory
setzt das per `lib.mkForce false` als bewusste Ausnahme. Vendor-Abstraktion in
`lib/gpu.nix` (`intel` / `amd` / `nvidia` / `none`).

## Pruefen

```bash
systemctl show jellyfin -p NRestarts --value      # muss 0 sein
sudo ss -tlnp | grep jellyfin                     # muss :5410 sein, nicht :8096
curl -s -o /dev/null -w '%{http_code}\n' http://jellyfin.local
```

## aus 552-audiobookshelf

# 552-audiobookshelf — Hoerbuecher und Podcasts

Port 5420. Antwortet mit **200**.

## Der seccomp-Fehler, der wortlos toetet

Das war L4. `SystemCallFilter` toetet den Prozess per **SIGSYS**, wenn ein
verbotener Syscall kommt — ohne Log, ohne Fehlermeldung, ohne Hinweis worauf.
Man sieht nur einen Dienst, der stirbt.

```nix
SystemCallErrorNumber = "EPERM";
```

Damit gibt der Kernel `EPERM` **zurueck**, statt zu toeten. Die Anwendung sieht
einen normalen Fehler, protokolliert ihn, und man weiss endlich welcher Syscall
das Problem ist.

> **Diese Zeile gehoert in jede seccomp-Haertung.** Ohne sie debuggst du blind.

## Warum 200 und nicht 302

Audiobookshelf liefert seine SPA direkt aus, ohne Login-Redirect. Ein 200 ist
hier also erwartbar — bei den *arr waere es verdaechtig.

## aus 553-navidrome

# 553-navidrome — Musikserver

Port 5430. Antwortet mit **302**.

## Die media-Gruppe muss explizit dazu

```nix
users.users.navidrome.extraGroups = lib.mkAfter [ "media" ];
```

Ohne das laeuft Navidrome, findet aber **keine Musik** — und meldet keinen Fehler,
sondern eine leere Bibliothek. Ein stiller Fehler, genau die Sorte, die am
laengsten unentdeckt bleibt.

`mkAfter`, damit der Host eigene Gruppen ergaenzen kann, ohne unsere zu verlieren.

## Wie das bewiesen wurde

Nicht durch „es geht jetzt", sondern per Gegentest: `chmod o-rx` auf das
Musikverzeichnis. Ohne Gruppenmitgliedschaft brach der Zugriff, mit ihr nicht.

> Ein Dienst, der laeuft, beweist nicht, dass deine Aenderung ihn zum Laufen
> gebracht hat. Nimm die Bedingung weg und sieh nach, ob es bricht.

## Feishin haengt hier dran

`554-feishin` spricht die Navidrome-API. Wer hier Port oder Adresse aendert, muss
dort `serverUrl` mitziehen.


## aus 554-feishin

# 554-feishin — alternative Oberflaeche fuer Navidrome

**Kein Prozess, keine Unit, kein belegter Port.** Reine statische Dateien, die
Caddy ausliefert. Die Nummer 544 existiert, damit der Dienst im Playback-Block
steht und die Registry vollstaendig ist; Port 5440 wird nie benutzt.

## Die Geschichte, wegen der dieser Abschnitt existiert

Bei Feishin wurde **dreimal hintereinander** falsch geurteilt:

1. „Das ist eine Desktop-App" — falsch
2. „Das muesste man erst paketieren" — falsch, `feishin-web` existiert in nixpkgs
3. „Es gibt drei Wege, alle mit Aufwand" — falsch, es sind statische Dateien

Der Mensch musste dreimal widersprechen und am Ende selbst die Links liefern.
Danach: *„sollte das noch einmal passieren, deinstalliere ich dich."*

**Was gefehlt hat:** ein Blick in den Paketinhalt. „Music Player" stand bei
`feishin` **und** `feishin-web`. Erst `find` im Store-Pfad zeigte den Unterschied
— `feishin.desktop` + `resources.pak` beim einen, `index.html` beim anderen.

Pflichtablauf: `.claude/rules/nix-recherche.md`.

## Feishin ersetzt Navidrome nicht

Es spricht dessen API (oder Jellyfin/OpenSubsonic). Ohne laufenden Musikserver
zeigt es nur eine Anmeldemaske. Die Assertion erzwingt deshalb, dass Navidrome,
Jellyfin oder eine explizite `serverUrl` gesetzt ist.

## `try_files` ist Pflicht

Single-Page-App: ohne `try_files {path} /index.html` ergibt jeder Deep-Link 404,
weil die Route nur im Browser existiert.
