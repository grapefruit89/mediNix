# 530-beschaffung — Prowlarr, Sonarr, Radarr, Lidarr, Readarr

Fuenf Dienste aus **einer** Fabrik (`lib/service-factory.nix`). Ports 5110–5150.

## nixpkgs besitzt Unit-Name, User und StateDirectory

Das Modul `nixos/modules/services/misc/servarr/*.nix` verdrahtet fest:

```nix
systemd.services.sonarr = { ... };
StateDirectory = "sonarr";
```

Daraus `media-512` zu machen hiesse, das Modul nicht zu benutzen und die Unit
selbst zu pflegen — dauerhafter Aufwand gegen den Strom. **Port und UID leiten
wir ab, Namen und Pfade nicht** (ADR-5042).

Konkret nuetzlich geworden: als Sonarr nicht startete, lautete die Zeile
`AppFolder /var/lib/sonarr is not writable`. Mit Nummernschema haette dort
`/var/lib/media-512` gestanden.

## tmpfiles legen als root:root an, wenn man den Eigentuemer vergisst

Das war L2 und aeussert sich genau als die Zeile oben. Jede `tmpfiles`-Regel fuer
ein State-Verzeichnis braucht Benutzer **und** Gruppe explizit.

## Die gemeinsame media-Gruppe ist der Sinn des Musters

Alle Dienste am selben Bibliothekspfad brauchen **dieselbe** Gruppe. Waere die
GID isomorph abgeleitet, bekaeme jeder Dienst seine eigene — Sonarr schriebe mit
1512, Jellyfin wollte mit 1541 lesen, `Permission denied`. Das ist der klassische
Docker-PUID/PGID-Fehler in Nix-Form.

> **Offen:** `registry.mediaGid = 5000` ist definiert, aber **nicht verdrahtet**.
> Real ist die GID 990, automatisch vergeben — also genau das Impermanence-Risiko,
> vor dem ADR-5042 warnt. Nicht so tun, als sei das erledigt.

## Pruefen

```bash
for s in prowlarr sonarr radarr lidarr readarr; do
  printf "%-10s %-8s %s\n" "$s" "$(systemctl is-active $s)" \
    "$(curl -s -o /dev/null -w '%{http_code}' http://$s.local)"
done
```

302 ist hier **richtig** — die *arr leiten auf ihr Login um.
