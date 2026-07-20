# LEARNINGS — was uns echte Hardware gelehrt hat

Laufendes Protokoll. Jeder Eintrag ist ein **Fehler, der wirklich passiert ist**,
mit Symptom, Ursache, Fix und der verallgemeinerten Regel.

**Warum diese Datei:** Ein Fehler, der nur im Chat behoben wurde, passiert
wieder. Ein Fehler, der als Regel formuliert ist, nicht.

---

# 2026-07-20 — Erster Start auf echter Hardware

**Maschine:** q958 — Fujitsu, 4 Kerne, 15 GB RAM, NixOS 26.05, x86_64
**Einbindung:** mediNix als Flake-Input, `grapefruitMedia.enable = true`
**Aktiviert:** Jellyfin, Sonarr, Prowlarr. Keine Domain, kein VPN, keine Auth.

## Ergebnis in einem Satz

Der Build war **fehlerfrei** — und trotzdem startete nur **einer von drei**
Diensten. Alle drei gefundenen Fehler sind reine Laufzeitfehler.

| | |
|---|---|
| `prowlarr.local` | ✅ HTTP 200 — lief auf Anhieb |
| `sonarr.local` | ✅ HTTP 200 — nach Fix L2 |
| `jellyfin.local` | ❌ HTTP 502 — L3 behoben, neues Problem offen |

---

## Die übergeordnete Lehre

> **`nix build` beweist Syntax und Typen. Er beweist nichts über Laufzeit.**

Keiner der drei Fehler war durch Evaluieren oder Bauen auffindbar. Alle drei
betreffen Dinge, die erst existieren, wenn systemd die Unit startet:
Dateisystem-Eigentümer, D-Bus-Berechtigungen, Prozess-Capabilities.

Die Konsequenz für dieses Repo: **ein grüner Build ist kein Freigabekriterium.**
Das Kriterium ist ein `nixosTest`, der die Dienste hochfährt (Issue #48). Bis
der existiert, gilt jeder Dienst als ungeprüft, bis ihn jemand hat laufen sehen.

---

## L1 — `{service}.local` wurde nie publiziert

**Symptom**

```
grapefruit-media-mdns: publishing aliases -> 192.168.2.73
Failed to create entry group: Not permitted
Duration: 48ms, status=0/SUCCESS
```

**Ursache**

`mdns.nix` setzte `publish.enable` und `publish.addresses`, aber **nicht**
`publish.userServices`. Der Schalter steuert `disable-user-service-publishing`
in der `avahi-daemon.conf` (nixpkgs `avahi-daemon.nix:39`). Steht der auf `yes`,
weist Avahi **jeden Client-Publish** ab — und `avahi-publish` ist genau so ein
Client.

Auch **als root** reproduzierbar. Es ist also keine Sandbox-Frage, sondern eine
Daemon-Richtlinie. Das war die entscheidende Messung: sie hat die naheliegende,
aber falsche Fährte (systemd-Härtung zu streng) sofort ausgeschlossen.

**Fix**

```nix
publish = {
  enable = true;
  addresses = true;
  userServices = true;   # ← ohne das kein einziger Alias
};
```

Danach: `Established under name 'sonarr.local'`.

**Regel**

> `publish.addresses = true` genügt **nicht**, wenn ein *externer Prozess*
> Einträge anlegt. `addresses` erlaubt dem Daemon, eigene Adressen zu
> veröffentlichen; `userServices` erlaubt es *Clients*, eigene Einträge
> beizusteuern. Zwei verschiedene Dinge mit ähnlich klingenden Namen.

### Zweiter, versteckter Fehler an derselben Stelle

Das Skript **endete mit Status 0**, obwohl jeder einzelne Publish gescheitert
war. Grund: die `avahi-publish`-Prozesse laufen im Hintergrund, `wait` ohne
lebende Kinder liefert 0. Damit greift `Restart = "on-failure"` nie — der
Dienst meldete Erfolg, während er nichts tat.

> **Regel:** Ein Dienst, der seinen eigenen Misserfolg nicht melden kann, ist
> schlimmer als einer, der abstürzt. Beim Starten von Hintergrundprozessen
> prüfen, ob mindestens einer lebt, und sonst mit ≠ 0 enden.

**Noch offen** — im Fix nicht enthalten, gehört in ein eigenes Issue.

---

## L2 — Sonarr startete nicht, Prowlarr schon

**Symptom**

```
[Trace] DiskProviderBase: Directory '/var/lib/sonarr' isn't writable.
SonarrStartupException: Sonarr failed to start: AppFolder /var/lib/sonarr is not writable
[Fatal] ConsoleApp: EPIC FAIL!
```

Dazu die verräterische Rechtelage:

```
/var/lib/sonarr              drwxr-xr-x  root:root       ← Elternverzeichnis
/var/lib/sonarr/MediaCover   drwxr-xr-x  sonarr:sonarr   ← Unterordner korrekt
```

**Ursache**

Die tmpfiles-Regel

```
d /var/lib/${name}/MediaCover 0755 ${name} ${name} -
```

legt das **Elternverzeichnis implizit mit an** — und zwar als `root:root`.
Danach kann niemand mehr die Rechte korrigieren, weil das Verzeichnis
existiert.

**Warum Prowlarr trotzdem lief** — das war der Schlüssel zur Diagnose:

| | Sonarr | Prowlarr |
|---|---|---|
| Benutzer | `User=sonarr` (statisch) | `DynamicUser=true` |
| `StateDirectory` | **fehlt** | `StateDirectory=prowlarr` |
| Verzeichnis | von tmpfiles als root angelegt | von systemd korrekt angelegt |

Prowlarr entging dem Fehler nur zufällig, weil `StateDirectory` das Verzeichnis
**vorher** mit richtigem Eigentümer erzeugt. Die *arr-Fabrik war an dieser
Stelle inkonsistent, ohne dass es jemandem aufgefallen wäre.

**Fix**

```nix
"d /var/lib/${name} 0750 ${name} ${name} -"          # ← MUSS zuerst stehen
"d /var/lib/${name}/MediaCover 0755 ${name} ${name} -"
```

Zusätzlich musste das bereits falsch angelegte Verzeichnis einmalig weg
(`rm -rf /var/lib/sonarr`) — ein Fix ändert keine bestehenden Eigentümer.

**Regel**

> Bei `systemd.tmpfiles.rules` **immer das Elternverzeichnis explizit
> deklarieren**, bevor ein Unterordner deklariert wird. Implizit angelegte
> Elternverzeichnisse gehören `root:root`.
>
> **Und:** Wenn von zwei gleichartigen Diensten einer läuft und einer nicht,
> ist der Unterschied zwischen ihnen die Diagnose. Nicht den kaputten allein
> anstarren — vergleichen.

---

## L3 — Jellyfin-Crash-Loop im preStart

**Symptom**

```
jellyfin-pre-start: install: cannot change ownership of
'/var/lib/jellyfin/config/system.xml': Operation not permitted
jellyfin.service: Control process exited, code=exited, status=1/FAILURE
```

**Ursache**

```bash
install -m 0640 -o jellyfin -g jellyfin "$src" "$dst"
```

Der `preStart` läuft **bereits als User `jellyfin`** und hat kein `CAP_CHOWN`.
`-o`/`-g` verlangen aber genau das. Der Eigentümer stimmt ohnehin, weil der
schreibende Prozess `jellyfin` ist — die Flags waren schlicht überflüssig.

**Fix**

```bash
install -m 0640 "$src" "$dst"
```

**Regel**

> `install -o/-g` im `preStart` nur, wenn die Unit als root läuft. Sobald
> `User=` gesetzt ist, sind die Flags falsch — nicht nur überflüssig, sondern
> abbruchauslösend.

### ⚠ Das eigentlich Beunruhigende an L3

Dieser Fehler stand in `Nix-Grok/CLAUDE.md` bereits **als erledigt markiert**:

> `[x] Jellyfin crash-loop: preStart CAP_CHOWN → systemd.tmpfiles.rules`

Der Fix war in Nix-Grok gelandet und **nie nach mediNix übernommen worden**.
Ein bereits gelöstes Problem ist erneut aufgetreten, weil zwei Kopien
existierten.

> **Regel:** Genau das ist der Preis der Doppelung — und der Grund, warum
> `Nix-Grok/modules/50-media` seit 2026-07-20 stillgelegt ist. Änderungen
> gehören ausschließlich hierher.

---

## Noch offen: Jellyfin-Migrations-Schleife

Nach L3 kommt Jellyfin bis zur Datenbank-Migration und fällt dort um.

```
NRestarts=13
Jellyfin.Server.Migrations.JellyfinMigrationService.MigrateStepAsync
SQLite Error 1: 'no such table: __EFMigrationsHistory'
```

**Stand:** Der `preStart`-Fehler ist weg, der Dienst lauscht zeitweise auf
`0.0.0.0:5001`, stürzt aber während der Migration ab. Ein Wipe von
`/var/lib/jellyfin` hat **nicht** gereicht.

**Vermutung, nicht belegt:** Die vorkonfigurierten Seeds (`system.xml`,
`encoding.xml`, …) werden im `preStart` eingespielt, *bevor* Jellyfin seine
Datenbank angelegt hat. Möglicherweise erwartet die Migration einen Zustand,
den die Seeds vorwegnehmen.

**Nächster Schritt:** Einmal ohne Seeds starten lassen. Läuft es dann durch,
ist die Ursache eingekreist.

---

## Was jetzt nachweislich funktioniert

Von einem **anderen Rechner im LAN** geprüft (nicht nur lokal auf q958):

```
http://sonarr.local     → HTTP 200
http://prowlarr.local   → HTTP 200
```

Damit ist die gesamte Kette bewiesen:

1. Avahi publiziert `{service}.local` auf die LAN-IP
2. Die IP-Ermittlung über die Default-Route funktioniert (kein hartkodiertes Subnetz)
3. Caddy nimmt auf `:80` an und trifft per Host-Matcher den richtigen Dienst
4. Das Port-Schema stimmt — Sonarr `5003`, Prowlarr `5006`
5. `localBypass` greift: `.local` ohne forward_auth, also ohne Login erreichbar

**Das ist der Zustand, auf den aufgebaut werden kann.**

---

## Ein Nebenbefund, der nichts mit mediNix zu tun hat

Der Speedport im Testnetz beantwortet für diese Netzwerkkarte **keine
DHCPv4-Anfragen**. `dhcpcd` wartete 10 s und fiel auf `169.254.x.x` zurück.
IPv6 lief die ganze Zeit sauber — weshalb `cache.nixos.org` (hat IPv6)
erreichbar war und GitHub (hat keins) nicht.

Für mediNix heißt das nichts, für die Fehlersuche viel:

> **Regel:** Wenn manche Hosts erreichbar sind und andere nicht, zuerst prüfen,
> ob es an IPv4/IPv6 liegt — nicht am Dienst.
