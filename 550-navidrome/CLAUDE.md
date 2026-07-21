# 550-navidrome — Musikserver

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

`544-feishin` spricht die Navidrome-API. Wer hier Port oder Adresse aendert, muss
dort `serverUrl` mitziehen.
