# 544-feishin — alternative Oberflaeche fuer Navidrome

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
