# 510-jellyfin — Medienserver

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
