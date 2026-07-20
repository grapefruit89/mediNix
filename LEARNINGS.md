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

**Endstand nach allen Fixes: 9 von 10 Diensten benutzbar.**

| Dienst | Ergebnis |
|--------|----------|
| `sonarr.local` | ✅ HTTP 200 — nach L2 |
| `radarr.local` | ✅ HTTP 200 — nach L2 |
| `readarr.local` | ✅ HTTP 200 — nach L2 |
| `lidarr.local` | ✅ HTTP 200 — nach L2 |
| `prowlarr.local` | ✅ HTTP 200 — lief auf Anhieb |
| `sabnzbd.local` | ✅ HTTP 200 |
| `navidrome.local` | ✅ HTTP 200 |
| `jellyseerr.local` | ✅ HTTP 200 |
| `audiobookshelf.local` | ✅ HTTP 200 — nach L4 |
| `jellyfin.local` | ❌ HTTP 502 — L3 und L5 behoben, Migration offen |

**Nicht getestet:** `560-recyclarr` (braucht geprüfte trash_ids, bewusst aus),
`590-usenet-confinement` (braucht WireGuard-Key), `525-provision` (braucht
API-Keys).

**Erzeugt nichts:** `exporters.enable = true` legt weder Units noch Ports an —
ungeklärt, eigener Prüfpunkt.

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

## L4 — Audiobookshelf starb an der eigenen Härtung

**Symptom**

```
Main process exited, code=dumped, signal=SYS, status=31/SYS
Scheduled restart job, restart counter is at 10
Start request repeated too quickly → start-limit-hit
```

`SIGSYS` heißt: ein Syscall wurde vom seccomp-Filter blockiert und der Prozess
dafür **getötet**. Kein Anwendungsfehler — die Härtung schoss den Dienst ab.

**Diagnose**

Gegentest mit leerem `SystemCallFilter`: Dienst startet sofort und lauscht auf
5008. Damit ist der Filter als Ursache **bewiesen**.

Der Widerspruch, der die Sache interessant macht:

| | Audiobookshelf (`node`) | Navidrome (`full`) |
|---|---|---|
| Filter | `@system-service`, `~@privileged` | dieselben **plus** `~@resources` |
| `SystemCallArchitectures` | **fehlte** | `native` |
| Ergebnis | ❌ SIGSYS | ✅ läuft |

Das `node`-Profil war **lockerer** und starb trotzdem.

**Fix**

Bewusst **kein** Erweitern der Allowlist auf Verdacht — welcher Syscall genau
blockiert wurde, ist nicht ermittelt (dafür bräuchte es die Syscall-Nummer aus
dem Audit-Log). Stattdessen:

```nix
SystemCallErrorNumber   = lib.mkForce "EPERM";   # nicht töten, sondern ablehnen
SystemCallArchitectures = lib.mkForce "native";  # fehlte gegenüber full
```

Abgewiesene Syscalls liefern jetzt `EPERM` statt `SIGSYS`. Node behandelt das
als normalen Fehler. **Die Härtung bleibt in Kraft** — nur die Reaktion ist
nicht mehr tödlich. Danach: HTTP 200.

**Regel**

> `SystemCallFilter` ohne `SystemCallErrorNumber` **tötet** den Prozess. Für
> Laufzeiten mit breiter Syscall-Nutzung (Node, JVM, .NET) ist `EPERM` die
> richtige Vorgabe: man verliert im Zweifel eine Funktion statt den Dienst.
>
> Und: `SystemCallArchitectures = "native"` gehört in **jedes** Profil. Fehlt
> es, können Syscalls über eine fremde ABI den Filter umgehen — das ist eine
> Lücke, kein gelockertes Profil.

> **Zur Ehrlichkeit:** Die Ursache ist eingegrenzt, nicht vollständig geklärt.
> Sobald die Syscall-Nummer bekannt ist, gehört sie explizit in die Allowlist
> und `SystemCallErrorNumber` kann wieder weg.

---

## L5 — Zustandsverzeichnisse fehlen: dasselbe Muster wie L2

**Symptom**

```
jellyfin.service: Failed to set up mount namespacing:
/var/lib/jellyfin: No such file or directory
```

Der Dienst kommt **gar nicht erst zum Start** — es scheitert schon das
Einrichten des Mount-Namespace.

**Ursache**

Die Unit setzt `ReadWritePaths=/var/lib/jellyfin`. Diese Direktive verlangt ein
**existierendes** Verzeichnis. Das Modul deklarierte aber nur Unterordner
(`/run/jellyfin-transcode`, `metadataDir/jellyfin`) und nie das
Zustandsverzeichnis selbst.

Solange irgendetwas es zufällig anlegt, fällt das nicht auf. Nach einem
`rm -rf /var/lib/jellyfin` — oder auf einer **frischen Installation** — ist der
Dienst tot.

**Fix**

```nix
"d /var/lib/jellyfin 0700 jellyfin jellyfin -"
"d /var/lib/jellyfin/config 0700 jellyfin jellyfin -"
"d /var/cache/jellyfin 0700 jellyfin jellyfin -"
```

**Regel**

> Das ist **dieselbe Fehlerklasse wie L2** — nur an anderer Stelle. Wer ein
> Verzeichnis in `ReadWritePaths`, `BindPaths` oder `StateDirectory` nennt,
> muss es auch deklarieren.
>
> Prüffrage für jedes Modul: *Läuft es nach `rm -rf` seines Zustands­verzeichnisses
> wieder an?* Wenn nein, ist es nicht neuinstallationsfest — und genau das
> merkt man erst bei jemand anderem.

---

## L6 — Jellyfin: bekannter Upstream-Fehler, **nicht unser Problem**

**Symptom**

```
InternalCodeMigration: Perform migration "20250420000000_CreateNetworkConfiguration"
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion") VALUES (…)
[FTL] Error: SQLite Error 1: 'no such table: __EFMigrationsHistory'
→ SIGABRT, Endlos-Neustart
```

**Ursache**

Ein Reihenfolgefehler **in Jellyfin 10.11 selbst**: die Migration schreibt in
`__EFMigrationsHistory`, bevor sie diese Tabelle anlegt. Auf einer frischen
Installation existiert die Tabelle nie — also scheitert es immer.

Belegt durch [jellyfin/jellyfin#17070](https://github.com/jellyfin/jellyfin/issues/17070):
identischer Stacktrace, identische Migration, Version 10.11.11 — dieselbe, die
nixpkgs 26.05 liefert. Der Melder hatte eine blanke Windows-Installation ohne
jede Vorkonfiguration.

> **Status upstream: „Closed as not planned", Projektfeld „Won't / Can't Fix".**
> Es wird nicht repariert.

**Zwei widerlegte eigene Hypothesen** — beide geprüft, beide falsch:

1. *„Die Config-Seeds bringen Jellyfin dazu, eine Altinstallation anzunehmen."*
   Gegentest mit neutralisiertem `preStart`: **derselbe Absturz.**
2. *„Ein Wipe von `/var/lib/jellyfin` räumt eine halbfertige DB weg."*
   Gewischt, mehrfach: **derselbe Absturz.**

Der Weg zur Erkenntnis war am Ende **kein Debugging**, sondern eine Suche in
den Upstream-Issues — genau das, was `AGENTS.md` Regel 0 vorschreibt und was
ich zu spät getan habe.

**Regel**

> **Bei einem Absturz in einem Fremdpaket zuerst die Upstream-Issues
> durchsuchen, bevor die eigene Konfiguration verdächtigt wird.** Zwei
> widerlegte Hypothesen und mehrere Wipes hätte eine einzige Suchanfrage
> erspart.
>
> Warnsignal: Wenn eine Fehlermeldung *inhaltlich unsinnig* ist — hier: eine
> Migration auf einer Installation, die nichts zu migrieren hat — ist der
> Fehler eher im Fremdcode als in der eigenen Konfiguration. Der Mensch hatte
> genau das sofort gesagt: *„wir haben keine db, wir brauchen nix migrieren"*.

**Lösungsweg (noch nicht umgesetzt)**

mediNix hat für exakt diesen Fall bereits eine Option — die Beschreibung nennt
den Anwendungsfall wörtlich:

```nix
grapefruitMedia.jellyfin.package = pkgs.…;   # "Downgrade bei einem kaputten
                                             #  Upstream-Release"
```

Zu prüfen: welche Jellyfin-Version ohne diesen Fehler in nixpkgs verfügbar ist
(10.10.x wäre der Kandidat), dann per `package`-Override festnageln und den
Grund hier verlinken.

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
