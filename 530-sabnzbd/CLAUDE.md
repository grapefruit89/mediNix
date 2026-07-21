# 530-sabnzbd — Usenet-Downloader

Port 5210. Antwortet mit **303** — das ist korrekt, nicht kaputt.

## Temp-Verzeichnis liegt im RAM

```nix
SABNZBD__MISC__TEMP_DIR = "/run/sabnzbd-tmp";
```

Entpacken erzeugt viele kurzlebige Schreibvorgaenge. Auf `/run` (tmpfs) schont
das die SSD spuerbar. Der Pfad muss in `ReadWritePaths` stehen, sonst
`226/NAMESPACE`.

## Konfiguration ueber Env-Variablen, nicht ueber die Datei

SABnzbd schreibt seine `sabnzbd.ini` selbst um. Wer die Datei deklarativ
hinlegt, verliert die Aenderung beim naechsten Start. Env-Variablen
(`SABNZBD__SEKTION__SCHLUESSEL`) gewinnen dagegen zuverlaessig.

## Bekannt offen

Der Newshosting-Servereintrag hat Platzhalter-Zugangsdaten
(`placeholder_user` / `placeholder_pass`). **Downloads laufen nicht**, bis der
Mensch echte Daten im Webinterface eintraegt. Das ist Absicht — Zugangsdaten
gehoeren nicht ins Repo.

Wer meldet „SABnzbd laeuft", muss das dazusagen. Der Dienst antwortet, er
funktioniert aber nicht.
