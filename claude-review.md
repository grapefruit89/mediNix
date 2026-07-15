# Architektur-Review: modules/50-media — Neuimplementierung vs. Altstand

**Reviewer:** Claude (kritischer Review-Architekt)
**Datum:** 2026-07-15
**Scope:** Kompletter Working-Tree-Stand von `modules/50-media/` (neu, uncommitted: 25 alte Dateien gelöscht, 500er-Struktur neu) verglichen mit dem alten Stand (Upload `grapefruit89-nix-grok`, 51-…59-Struktur mit `my.*`-Namespace). Zusätzlich geprüft: Integration in den Rest des Repos (rollout.nix, server-map.nix, service-enable.nix, forbidden-tech.nix, 60-apps, media-secrets.nix).

---

## 1. Executive Summary

Die Neuimplementierung verfolgt ein klar erkennbares und **legitimes Ziel**: Extraktion des Media-Stacks in ein **portables, eigenständiges Modul** mit einem einzigen Options-Namespace (`grapefruitMedia.*`), vendored Libs und parametrisierten Pfaden. Das ist als Richtung richtig gedacht und an mehreren Stellen sauber umgesetzt (Options-Design, Pfad-Parametrisierung, Erhalt der besten Altbestandteile wie tmpfs-Transcode, Leak-Verify, On-Demand-Sockets).

**Aber:** In der aktuellen Form ist der Stand **nicht deploybar und sicherheitstechnisch ein deutlicher Rückschritt**. Die drei schwerwiegendsten Punkte:

1. **Das Repo evaluiert nicht mehr.** Der alte Options-Namespace (`my.services.jellyfin` u. a.) wurde ersatzlos gelöscht, wird aber weiterhin von `machines/q958/rollout.nix` gesetzt. `nixos-rebuild` schlägt mit „option does not exist" fehl. Gleichzeitig setzt nichts im Repo `grapefruitMedia.enable = true` — selbst nach Eval-Fix wäre der gesamte Media-Stack aus.
2. **Die Authentifizierungsschicht ist stillschweigend verschwunden.** Die *arr-Apps werden weiterhin auf `AUTH__METHOD=External` gezwungen (= „vertraue dem vorgelagerten Auth-Proxy"), aber der Forward-Auth-Proxy (Pocket-ID/oauth2-proxy hinter Caddy) existiert im neuen Modul nicht mehr. In Kombination mit der neu geöffneten Firewall (Punkt 3) ergibt das **unauthentifizierten Admin-Zugriff auf Sonarr/Radarr/Prowlarr/… aus dem LAN**.
3. **`default.nix` öffnet pauschal 13 Ports in der Firewall** — das exakte Gegenteil der alten Zero-Exposure-Haltung (`openFirewall = false` überall, alles hinter Caddy auf Loopback).

Dazu kommen mehrere Komponenten in Prototyp-Qualität (Secrets-Portal, Feishin, geteilter API-Key mit vermutlich wirkungslosem Env-Var-Namen) und der ersatzlose Wegfall der gesamten deklarativen Provisionierung (`56-arr-sync`).

**Gesamturteil:** Gute Extraktionsidee, solide übernommener Kern — aber der Umbau hat die zwei Eigenschaften geopfert, die den Altstand ausgezeichnet haben: *Sicherheit als Default* und *deklarative Vollständigkeit*. Vor einem Merge müssen mindestens die KRITISCH-Findings behoben werden.

| Dimension | Bewertung | Kurzbegründung |
|---|---|---|
| Security | **mangelhaft** | Auth-Schicht weg, Firewall auf, unauthentifiziertes Secrets-Portal, geteilter API-Key, `:latest`-Container |
| Korrektheit | **mangelhaft** | Eval-Bruch im Repo, API-Key-Env-Var vermutlich wirkungslos, Portal-ExecStart vermutlich nicht parsebar, Feishin-Netzwerk-Bug |
| Wartbarkeit | **befriedigend** | Options-Design gut, aber Code-Duplikation (on-demand), tote Optionen, Meta-Header/ADR-Verweise entfernt |
| Performance/Ressourcen | **gut** | Memory-Policy, tmpfs-Transcode, On-Demand-Stop vollständig erhalten |

---

## 2. Stärken der Neuimplementierung

Diese Punkte sind echte Verbesserungen gegenüber dem Altstand und sollten bei jeder Überarbeitung erhalten bleiben.

### 2.1 Portabilität als Architekturziel (default.nix)
- **Ein Namespace, eine Oberfläche:** `grapefruitMedia.*` bündelt Enable-Flags, Ports, Hardware, Locale, Storage, Secrets-Pfade und VPN in einer einzigen, typisierten, mit `description` dokumentierten Options-Deklaration (`default.nix:25–222`). Der Altstand verteilte das auf `my.services`, `my.ports`, `my.users.registry`, `my.configs.hardware`, `my.configs.locale`, `my.policy.onDemand`, `my.media.*` — für Außenstehende kaum navigierbar. Das neue Design ist als Modul-API deutlich besser.
- **Pfad-Parametrisierung:** `storage.mediaRoot` und `storage.metadataDir` ersetzen die hartkodierten `/data/...`- und `/mnt/fast_pool/metadata/...`-Pfade des Altstands. Konsequent durchgezogen in 510/520/540/550 und on-demand.nix. Das war die größte Portabilitätsbremse des Altcodes.
- **VPN-Parametrisierung:** `vpn.interface` und `vpn.dns` statt hartkodiertem `privado` (`590:26,131–137`). Der Altstand war fest mit dem Privado-Modul verdrahtet.
- **Ports flach und typisiert** (`types.port`, R4) statt zentraler Registry — für ein Standalone-Modul die richtige Wahl.

### 2.2 Die besten Altbestandteile wurden erhalten
- **Jellyfin-Kern (510):** tmpfs-Transcode mit 6-GB-Limit, RAM-adaptiver Cleanup (65 %/80 %-Schwellen), Path-Unit mit TriggerLimit + rebuildGuard, Config-Seeds via `sed`-Templating mit `cmp`-Idempotenz, ExecStopPost-Cleanup, VA-API-Setup inkl. `intel-compute-runtime-legacy1`-Kommentarwissen für Gen 9, `AF_NETLINK`-Fix für .NET — alles 1:1 übernommen. Sogar verbessert: der MetadataPath im system.xml wird jetzt per `sed` auf `${metadataDir}` umgeschrieben statt hartkodiert (`510:35`).
- **Leak-Verify (590):** Lock-File, Cache-TTL, operstate-Sonderfall für WireGuard, Retry-Loops, Fail-Closed-Stop von sabnzbd/prowlarr bei Leak — vollständig erhalten und jetzt interface-parametrisiert. Die Zusammenlegung von `57-usenet-confinement/default.nix` + `leak-verify.nix` in eine Datei erhöht die Kohäsion.
- **Exportarr (570):** `LoadCredential` + `DynamicUser` + `ExecCondition`-Key-Validator + volle Hardening-Palette unverändert — das war einer der am besten gehärteten Teile des Altstands.
- **On-Demand-Lib, Memory-Policy, Service-Factory, Rebuild-Guard:** als vendored Kopien unter `lib/` erhalten, damit ist das Modul tatsächlich aus dem Repo herauslösbar.
- **Recyclarr-Profile (560):** TRaSH-IDs, Score-Systematik (10000er-Sprachgates, −35000-Blocks, Repack-Staffelung) und Quality-Definitions identisch übernommen.

### 2.3 Neue, sinnvolle Konzepte
- **Chamäleon-Ingress (500):** Die Idee `auto | global | standalone` — bei vorhandenem globalem Caddy einklinken, sonst eigene Instanz — ist für ein portables Modul genau das richtige Muster. (Die Umsetzung ist unfertig, s. H6, aber das Konzept trägt.)
- **`secrets.*`-Pfad-Optionen als sops-nix-Brücke:** Alle Secret-Pfade sind Optionen mit Defaults unter `secretsDir` — ein Konsument kann sie auf sops-nix-Pfade umbiegen, ohne das Modul zu ändern. Gutes Interface-Design.
- **Assertion-Disziplin teilweise erhalten:** renderDevice-Assertion (510:51–56), Recyclarr-Assertion (560:387–392).

---

## 3. Kritische Findings (Merge-Blocker)

### K1 — Repo-Integration gebrochen: Evaluation schlägt fehl, Stack ist tot
**Dateien:** `default.nix` (neu) vs. `machines/q958/rollout.nix:93–103,128–…`, `machines/q958/default.nix:40`

Der alte `50-media/default.nix` deklarierte `options.my.services.{jellyfin,jellyseerr,sonarr,radarr,readarr,prowlarr,sabnzbd,audiobookshelf,navidrome,lidarr}`; `57-usenet-confinement` deklarierte `my.services.usenet-confinement`, `58-recyclarr` `my.services.recyclarr`, `56-arr-sync/*` den ganzen `my.media.sync.*`-Baum, `59-exportarr` `my.media.exporters`. **Alle diese Deklarationen sind gelöscht.** Gleichzeitig setzt `rollout.nix` weiterhin:

```nix
my.services.jellyfin.enable = erstAb 6;    # rollout.nix ~93
my.services.usenet-confinement.enable = erstAb 6;
my.services.recyclarr.enable = erstAb 6;
my.media.sync.prowlarr.indexers = [ … ];   # rollout.nix 128 ff.
```

→ `error: The option 'my.services.jellyfin' does not exist.` Das Repo baut nicht.

Zusätzlich: **Kein einziger Konsument setzt `grapefruitMedia.enable`** (grep über das gesamte Repo: null Treffer außerhalb von 50-media). Selbst nach Behebung der Eval-Fehler wären Jellyfin, *arr, SABnzbd etc. auf q958 schlicht abgeschaltet. Auch `lib/server-map.nix` (SSO-Flags, UIDs), `lib/service-enable.nix` (Ingress-Generator liest `config.my.services.*`) und `machines/q958/media-secrets.nix` (provisioniert per-Service-Keys nach altem Schema) laufen ins Leere bzw. gegen ein Modul, das sie nicht mehr kennt.

**Empfehlung:** Entweder (a) eine dünne Adapter-Schicht, die `my.services.X.enable → grapefruitMedia.X.enable` mappt und `grapefruitMedia.{domain,ports,hardware,locale,storage,secrets}` aus den bestehenden `my.*`-Werten befüllt, oder (b) rollout.nix/server-map/service-enable/media-secrets konsequent auf den neuen Namespace umstellen — dann aber vollständig und in einem Commit. Der jetzige Zwischenzustand ist der schlechteste aller Welten.

### K2 — Auth/SSO-Schicht stillschweigend entfernt: unauthentifizierter Admin-Zugriff
**Dateien:** `520-arr-stack/default.nix:87–91`, `lib/service-factory.nix:78–130`, `default.nix:224–240`

Die Kausalkette:
1. `520` setzt weiterhin `"${nameUpper}__AUTH__METHOD" = lib.mkForce "External"` — die *arr-Apps deaktivieren damit ihre **eigene** Login-Maske und vertrauen darauf, dass ein vorgelagerter Proxy authentifiziert.
2. Im Altstand existierte dieser Proxy: `mode = "sso"` in der Factory erzeugte einen Caddy-vHost mit `forward_auth` → Pocket-ID/oauth2-proxy (vgl. Meta-Header von alt-51: „Caddy forward_auth → Pocket-ID"). In der **vendored Factory ist `mode` ein toter Parameter**: `vhost` und `doIngress` werden berechnet und nie verwendet (`service-factory.nix:102–104`), es wird kein Caddy-Eintrag erzeugt. Der Aufrufer glaubt SSO zu konfigurieren; es passiert nichts.
3. Die *arr-Apps binden per Default an `0.0.0.0` (die NixOS-Module setzen nur den Port, keine Bind-Adresse — anders als SABnzbd/Navidrome/ABS, die explizit `127.0.0.1` bekommen).
4. `default.nix:225–239` öffnet die Firewall für genau diese Ports (s. K3).

**Ergebnis:** Jeder Client im LAN erreicht `http://<host>:5003` (Sonarr) etc. und hat wegen `AUTH__METHOD=External` **vollen, unauthentifizierten Admin-Zugriff** — inklusive der Möglichkeit, über die eingebauten „Connect"/Custom-Script-Funktionen der *arr-Apps Code auf dem Host auszuführen. Das ist die schwerste einzelne Regression des Umbaus.

**Empfehlung:** Kurzfristig `AUTH__METHOD` auf `Forms` zurückstellen, solange kein Forward-Auth existiert, plus explizite Bind-Adresse `127.0.0.1` für alle *arr-Apps. Mittelfristig: Forward-Auth in den Chamäleon-Ingress einbauen oder `mode="sso"` ehrlich entfernen und per Assertion erzwingen, dass `AUTH__METHOD=External` nur mit aktivem Auth-Proxy kombinierbar ist.

### K3 — Firewall-Öffnung aller Service-Ports
**Datei:** `default.nix:224–240`

```nix
networking.firewall.allowedTCPPorts = lib.mkDefault [ …alle 13 Ports… ];
```

Der Altstand hatte **kein einziges** `openFirewall = true` und keinen `allowedTCPPorts`-Eintrag im Media-Modul — Exposition lief ausschließlich über Caddy (443) mit forward_auth. Die neue Liste öffnet u. a. auch `secrets-portal` (5011!) und `libreseerr`. Für die Dienste, die auf 127.0.0.1 binden, ist die Öffnung wirkungslos (unnötige Angriffsfläche in der Policy), für die *arr-Apps ist sie zusammen mit K2 fatal. Widerspricht außerdem direkt dem Sicherheitskurs der letzten Commits (`feat(security): Access-Policy — jarvis-only SSH …`).

**Empfehlung:** Ersatzlos streichen. Ein portables Modul darf niemals per Default LAN-Ports öffnen; wenn überhaupt, hinter einer expliziten Option `exposePortsToLan = false` mit warnender Description.

### K4 — Geteilter API-Key für alle *arr-Dienste + vermutlich wirkungsloser Env-Var-Name
**Datei:** `520-arr-stack/secrets-generator.nix:28–42`

Zwei getrennte Probleme:

1. **Ein Key für fünf Dienste.** `openssl rand -hex 16` → derselbe Key wird als `SONARR__API_KEY`, `RADARR__API_KEY`, … in fünf env-Dateien geschrieben. Der Altstand hielt per-Service-Keys (`/var/lib/secrets/sonarr_api_key`, …), provisioniert und validiert durch `media-secrets.nix` + `arr-provision`. Kompromittierung eines Dienstes kompromittiert jetzt den gesamten Stack; Key-Rotation ist nur noch global möglich. Blast-Radius-Isolation weg.
2. **`SONARR__API_KEY` ist mit hoher Wahrscheinlichkeit wirkungslos.** Die Servarr-Env-Konvention ist `SECTION__KEY` — der API-Key liegt in der Auth-Sektion, korrekt wäre `SONARR__AUTH__APIKEY`. Der eigene Code benutzt dieselbe Konvention korrekt eine Datei weiter (`520:88`: `SONARR__AUTH__METHOD`). `SONARR__API_KEY` parst als Sektion „API", Key „KEY" — das mappt auf nichts. **Konsequenz:** Die Apps behalten ihren selbstgenerierten Key aus `config.xml`, während Recyclarr (`560:401,414`: `api_key._secret = arrApiKeyFile`) und Exportarr (`570:92–110`) mit dem Generator-Key anfragen → **401, beide Subsysteme funktionslos.** Der Altstand löste genau das mit `arr-sync-keys` (Key in config.xml schreiben + Neustart + Validierung).
3. Nebenbefunde: Der Generator läuft als root ohne jegliches Hardening, schreibt env-Dateien auch für deaktivierte Dienste, und ist nur an `cfg.enable` gebunden (nicht an die einzelnen Service-Enables).

**Empfehlung:** Per-Service-Keys erzeugen, via `SONARR__AUTH__APIKEY` injizieren (und verifizieren, dass die eingesetzten *arr-Versionen das honorieren — sonst config.xml-Sync wie im Altstand), Recyclarr/Exportarr auf die per-Service-Dateien zeigen lassen.

### K5 — Secrets-Portal (591): unauthentifiziert, kaputt und vermutlich nicht einmal startfähig
**Datei:** `591-secrets-portal/default.nix`

Das Portal ist in der aktuellen Form ein Prototyp mit mehreren unabhängigen Blockern:

1. **Keinerlei Authentifizierung:** `POST /save-usenet`, `/save-vpn`, `/save-indexers` überschreiben VPN-/Usenet-/Indexer-Credentials. Der Ingress (500) proxied diese Routen aktiv (`route /save-usenet` und `@secrets host media-secrets.local`) — über Port 80, Klartext-HTTP, ohne Auth. Jeder LAN-Teilnehmer kann Credentials **injizieren** (z. B. den VPN-Key durch einen eigenen ersetzen → Traffic-Umleitung) oder per Dauer-POST die Reload-Kaskade triggern (s. u.).
2. **Permissions-Deadlock:** Der Generator (K4) legt `secretsDir` mit `chmod 700` als root an; das Portal läuft als `nobody`. `ReadWritePaths` hebt nur die systemd-Sandbox auf, nicht die DAC-Rechte → jeder Schreibversuch endet in `EACCES`. Das Portal kann seine Kernfunktion nicht ausführen.
3. **`User = "nobody"` ist ein Anti-Pattern:** nobody ist ein geteiltes Konto; jeder andere nobody-Prozess könnte die (dann nobody-eigenen) Secret-Dateien lesen. Ein dedizierter `DynamicUser` bzw. Systemuser wäre Pflicht.
4. **ExecStart vermutlich nicht parsebar:** Der mehrzeilige Python-Code steckt als einfach gequoteter String direkt in `ExecStart`. systemd-Unit-Files erlauben keine rohen Newlines innerhalb eines quoted Arguments (Fortsetzung nur via Backslash) — die Unit wird beim Laden mit hoher Wahrscheinlichkeit verworfen. Korrekt: `pkgs.writers.writePython3Bin` o. ä.
5. **Kein Hardening** im Vergleich zum Rest des Moduls: kein `SystemCallFilter`, kein `PrivateDevices`, kein `CapabilityBoundingSet`, kein `IPAddressAllow`.
6. **Reload-Watchdog als DoS-Vektor:** `media-secrets-reload` macht `reload-or-restart sabnzbd prowlarr` bei jeder Dateiänderung — zusammen mit dem unauthentifizierten POST kann ein LAN-Client die Dienste in einer Restart-Schleife halten.
7. Das Portal ist **unconditional** an `cfg.enable` gebunden — es gibt nicht einmal eine eigene Enable-Option, obwohl `my.services.secrets-portal` in `service-enable.nix` als Konzept existiert.

**Empfehlung:** Komponente vor dem Merge entfernen oder hinter `mkEnableOption` + Auth (mindestens Basic-Auth im Caddy, besser forward_auth) + dediziertem User + `writePython3Bin` neu bauen. In der jetzigen Form ist sie ein Sicherheits- und Stabilitätsrisiko ohne Funktionsnutzen (wegen 2 und 4 funktioniert sie ohnehin nicht).

### K6 — OCI-Container verletzen Repo-Policy und duplizieren ein Native-Modul
**Dateien:** `551-feishin/default.nix`, `580-libreseerr/default.nix` vs. `lib/forbidden-tech.nix:50`, `modules/60-apps/62-libreseerr.nix`

1. **Policy-Verstoß:** `lib/forbidden-tech.nix` erzwingt `[POL-FT-001] !virtualisation.docker.enable`. `virtualisation.oci-containers` zieht je nach Backend Docker hoch; `551` referenziert explizit `systemd.services."docker-feishin"` — also die Docker-Annahme. Entweder knallt POL-FT-001, oder (bei Podman-Backend) ist die Unit-Referenz `docker-feishin` falsch und erzeugt eine funktionslose Geister-Unit. Auch die dokumentierte Projektentscheidung „hermes nativ statt Podman (2026-06-26)" (rollout.nix) zeigt: Container sind in diesem Repo bewusst unerwünscht.
2. **`:latest` + `--pull=always`** (580) bedeutet: bei jedem Start wird ungeprüfter, neuester Fremdcode von `ghcr.io/zamnzim/libreseerr` gezogen — das Gegenteil von reproduzierbarem NixOS und ein Supply-Chain-Risiko. Der Altstand baute Libreseerr aus `packages/libreseerr` selbst und betrieb es nativ mit Factory-Hardening (siehe `60-apps/62-libreseerr.nix`, Meta-Header wörtlich: „nativ, kein Docker").
3. **Kollision:** `62-libreseerr.nix` (nativ, User `libreseerr`, `/var/lib/libreseerr`, Port aus `my.ports`) existiert weiter und wird via rollout Stufe 7 aktiviert. `580` legt denselben Pfad `/var/lib/libreseerr` mit **uid 1000** (!) an — uid 1000 ist der interaktive Host-User. Zwei Module, ein State-Verzeichnis, zwei Owner.
4. **Feishin-Netzwerk-Bug (551:21):** `SERVER_URL = "http://127.0.0.1:${ports.navidrome}"` — im Bridge-Netz des Containers ist 127.0.0.1 der **Container selbst**, nicht der Host. Feishin kann Navidrome so nie erreichen. Zudem: kein tmpfiles-Eintrag für das Volume `${metadataDir}/feishin`, hartkodierte `PUID/PGID = 1000`, `after = [ "docker-navidrome.service" ]` referenziert eine Unit, die nicht existiert (Navidrome läuft nativ).

**Empfehlung:** 580 streichen (natives 62-libreseerr existiert und ist besser) oder auf das Nix-Package umstellen. Feishin — wenn überhaupt — als statisches Web-Frontend nativ ausliefern (Feishin ist eine SPA; ein Caddy-`file_server` über dem gebauten Bundle wäre policy-konform, reproduzierbar und ohne Container-Overhead).

---

## 4. Hohe Findings

### H1 — Deklarative Provisionierung (56-arr-sync) ersatzlos gestrichen
**Alt:** 9 Dateien, ~1000 Zeilen: `keys.nix` (API-Keys in config.xml + Restart), `download-clients.nix` (SABnzbd-Registrierung in allen *arrs), `prowlarr.nix` (Indexer- + App-Sync inkl. syncLevel, Backup-Indexer), `seerr.nix` (kompletter Jellyseerr-Bootstrap), `jellyfin-sync.nix` (Admin-Bootstrap, Library-Setup, Extra-User, Intro-Scan), `locale.nix` (Jellyfin/SABnzbd-Locale + Kategorien), `profiles.nix`, `settings.nix` — orchestriert über `packages/arr-provision` mit sauberen after/wants-Ketten.

**Neu:** Nichts davon. Der „Ersatz" (secrets-generator) deckt <10 % ab und ist defekt (K4).

Das ist die größte funktionale Lücke: Nach einem Fresh-Deploy des neuen Moduls müssen Download-Clients, Indexer, Root-Folder, Seerr-Anbindung, Jellyfin-Admin und Locale **manuell im UI** konfiguriert werden — exakt der Zustand, den der Altstand mit erheblichem Aufwand deklarativ gelöst hatte. Die `rollout.nix`-Konfiguration (TreasureMaps-Indexer etc.) hat keinen Adressaten mehr.

Falls der Scope-Cut bewusst ist (Portabilität vor Vollständigkeit): dann gehört das prominent dokumentiert, und `packages/arr-provision` sollte als optionale Ergänzungsschicht angebunden bleiben, statt zu verwaisen.

### H2 — UID/GID-Registry aufgegeben → Ownership-Drift
**Alt:** `uids.sonarr`/`gids.sonarr` aus `my.users.registry` mit `lib.mkForce` gepinnt (arr-helper:1582–1590, sabnzbd alt:516–521); `server-map.nix` dokumentiert die UIDs (5003, 5004, …) bis heute.
**Neu:** `isSystemUser = true` ohne uid/gid (`520:71–77`, `530:35–45`) → dynamische Allokation.

Auf Systemen mit Impermanence, ZFS-Datasets oder schlicht überlebenden `/data`- und `metadataDir`-Bäumen führt uid-Drift zwischen Reinstalls/Reihenfolgeänderungen zu verwaisten Dateien und schwer diagnostizierbaren Permission-Fehlern — genau das Problem, das die Registry (ADR-011 „unified port-uid schema") gelöst hatte. Für ein portables Modul wäre eine Option `uidBase ? null` (wenn gesetzt: pinnen) der saubere Kompromiss.

### H3 — `persist.extraPaths` hat keinen Konsumenten (stille Datenverlust-Falle)
`grapefruitMedia.persist.extraPaths` wird fleißig befüllt (Factory:127–129, 530:19, 580:32), aber **nichts im Repo liest diese Option** (grep: null Treffer außerhalb 50-media). Der Altstand schrieb in `my.impermanence.extraPaths`, das vom Impermanence-Modul konsumiert wurde (rollout: `my.impermanence.enable = erstAb 9`). Wer sich auf `persist.enable = true` verlässt, verliert bei aktivem Impermanence **den kompletten Media-State beim Reboot** — der gefährlichste Typ Bug: sieht konfiguriert aus, tut nichts. Zudem inkonsistent: 530 setzt extraPaths unconditional, die Factory nur bei `persist.enable`.

### H4 — On-Demand-Pfad: fehlende tmpfiles + massive Code-Duplikation
**Dateien:** `500-media-ingress/on-demand.nix`, `520-arr-stack/default.nix:93–96`

1. **Bug:** Die tmpfiles-Regeln für `metadataDir` und `/var/lib/<name>/MediaCover` liegen neu **innerhalb** des `(!onDemand)`-Zweigs (520:93–96). Im Altstand waren sie ein eigener, immer aktiver `mkIf (metadataDir != null)`-Zweig (arr-helper:1625–1630). Folge: Bei `onDemand.enable = true` existieren `${metadataDir}/lidarr` und das MediaCover-Ziel ggf. nicht → `BindPaths` (on-demand.nix:50) schlägt fehl → Backend startet nicht.
2. **DRY-Regression:** Der Altstand hatte `mkArrOnDemand` als Funktion (alt-58:799–865); die Neuimplementierung kopiert den Lidarr-Block als Readarr-Block (~50 Zeilen ×2, on-demand.nix:22–130), inklusive redundanter Wiederholung von `UPDATE__BRANCH`/Env-Werten, die **auch** in `520-arr-stack` definiert sind — zwei Quellen der Wahrheit, die auseinanderlaufen werden.
3. Strukturell fragwürdig: On-Demand liegt unter `500-media-ingress/`, hat aber mit Ingress nichts zu tun; `default.nix` importiert das Verzeichnis **und** die Einzeldatei — funktioniert, ist aber inkonsistent.

### H5 — Observability-Integration entfernt
**Alt (59-exportarr):** Auto-Enable der Exporter bei aktivem VictoriaMetrics (`mkDefault vmEnabled`), automatische Registrierung der `scrape_configs` (alt:1511–1513), `after/wants` auf `arr-sync-keys`.
**Neu (570):** Exporter starten (sofern manuell enabled), aber **niemand scrapt sie** — kein scrape_config, keine VM-Kopplung. Zusammen mit K4 (falscher Key → 401) ist die Metrik-Pipeline doppelt tot. Auch der `OnFailure → alerting-onfailure.service`-Hook der Leak-Verify (alt:2989–2991) ist entfallen — VPN-Leaks werden nicht mehr alarmiert, nur noch geloggt.

### H6 — Chamäleon-Ingress: Konzept gut, Umsetzung ein Stub
**Datei:** `500-media-ingress/default.nix`

- **Standalone-Modus:** Site-Adresse `http://localhost:80, http://127.0.0.1:80` matcht nur den Host-Header `localhost`/`127.0.0.1`. LAN-Clients, die `jellyfin.grapefruit-media.local` oder die Server-IP aufrufen, matchen **keinen** Site-Block. Der `@feishin host feishin.*`-Matcher innerhalb des localhost-Blocks ist damit unerreichbar. Faktisch funktioniert Standalone nur via SSH-Tunnel/curl vom Host selbst.
- **Routing-Lücken:** Es gibt Routen für Secrets-Portal, Feishin und einen Catch-All auf Jellyfin. Sonarr, Radarr, Prowlarr, SABnzbd, Navidrome, ABS, Jellyseerr: **keine vHosts**, weder standalone noch global. Der Altstand routete jeden Dienst über dns-map + Factory. `grapefruitMedia.domain` („Base domain used for local ingress routing e.g. *.grapefruit-media.local") verspricht Subdomain-Routing, das nicht existiert.
- Der 443-Block antwortet mit Klartext-HTTP `"HTTPS OK"` — kein TLS, irreführender Platzhalter.
- Positiv: Hardening der caddy-media-Unit (CAP_NET_BIND_SERVICE-only, strict, eigener User) ist ordentlich.

### H7 — Usenet-Confinement: Guards und Alerting abgeschwächt
- **Kein Gate auf VPN-Existenz:** Alt: `lib.mkIf (cfg.enable && privado.enable)`. Neu: keinerlei Assertion, dass `vpn.interface` von irgendetwas provisioniert wird. Ohne WireGuard-Config hängen sabnzbd/prowlarr ewig an `BindsTo=sys-subsystem-net-devices-….device` — fail-closed (gut), aber ohne jede Diagnose-Hilfe (Assertion mit Klartext wäre billig).
- **DNS-Default 1.1.1.1** statt Provider-DNS aus `privado.dns`: Die Queries laufen dank `RestrictNetworkInterfaces` zwar durch den Tunnel, aber das alte fail-closed-DoT-Konzept (ADR-1001) ist damit stillschweigend aufgegeben.
- `lib.recursiveUpdate sandboxAttrs { serviceConfig.ExecStartPre = … }` (590:200–209) funktioniert hier, ist aber fragil: Sobald `sandboxAttrs.serviceConfig` selbst ein `ExecStartPre` bekommt, überschreibt das Update es kommentarlos. `lib.mkMerge` wäre das idiomatische Werkzeug.

---

## 5. Mittlere Findings

- **M1 — Tote Optionen im Recyclarr-Modul (560):** `recyclarr.quality`, `primaryLanguage`, `secondaryLanguage` werden in `default.nix:61–75` deklariert (mit enum-Typen und Beschreibung) und in `560` **komplett ignoriert** — die Profile sind hart auf German/English 1080p verdrahtet. Eine API, die Konfigurierbarkeit verspricht und nicht liefert, ist schlechter als keine Option. Entweder implementieren oder entfernen.
- **M2 — Dead Code in der vendored Factory:** `mode`, `extraCaddy`, `caddyOnly`, `manageIngress`, `ipAllow`, `host`, `socketPath`, `upstreamHost` — überwiegend berechnete, nie genutzte Parameter (`service-factory.nix:78–106`). Jeder Aufrufer, der `mode = "sso"` übergibt, wird getäuscht (s. K2). Die Signatur sollte auf das reduziert werden, was die Factory tatsächlich tut.
- **M3 — Meta-Header und ADR-Verweise entfernt:** Der Altstand trug in jeder Datei YAML-Meta (layer/role/purpose/docs/ADRs). In der Neuimplementierung haben nur die vendored Libs Header; alle Service-Module (510–591) sind blank. Damit reißen die Verweise auf `docs/adr/5031-usenet-vpn-sandbox.md`, `docs/memory_oom.md`, ADR-007 etc. ab — das Repo hat erkennbar eine Meta-/SPEC_REGISTRY-Konvention, die hier verletzt wird. Auch wertvolle Betriebskommentare (z. B. das OIDC-Setup-Rezept in alt-55-navidrome:686–694) sind gestrichen.
- **M4 — `with lib;`** in `default.nix`, `500`, `551`, `591` — im Rest des Repos (und in den übrigen neuen Dateien) wird konsequent `lib.` qualifiziert; `with lib;` gilt in nixpkgs als Anti-Pattern (Scope-Verschattung, schlechtere Fehlermeldungen). Der letzte Hygiene-Commit („nixfmt RFC-Style auf 14 Module") zeigt, dass das Repo hier Standards hat.
- **M5 — `metadataDir`-Default auf Root-FS:** `/var/lib/media-metadata` als Default verschiebt die Artwork-/Metadata-Last (im Altstand bewusst auf `fast_pool`, vgl. Kommentar in jellyfin-system.xml: „Metadaten auf fast_pool — nicht in /var/lib") unauffällig auf die Root-Disk. Für ein portables Modul ist ein Default okay, aber die Description sollte die Performance-Implikation nennen; auf q958 muss der Wert zwingend gesetzt werden.
- **M6 — Exportarr-Gating unvollständig:** `mkExporter` prüft `cfgGlobal.${service}.enable && cfg.enable`, aber nicht `cfgGlobal.enable` (570:44) — bei `grapefruitMedia.enable = false` und gesetzten Flags entstehen Exporter-Units für nicht existierende Dienste. Alle anderen Module gaten korrekt auf `cfg.enable`.
- **M7 — Locale-Default-Wechsel de→en:** Portabilitäts-technisch richtig, aber ein stiller Verhaltenswechsel für q958 (Jellyfin-Metadaten, SABnzbd-UI). Muss beim Umstieg explizit `locale = { language = "de"; default = "de_DE.UTF-8"; }` gesetzt werden — sonst regressiert die deutsche Metadaten-Präferenz. Randfall unverändert aus alt geerbt: `lib.substring 3 2` bricht bei Locales wie `C.UTF-8`.
- **M8 — `jellyseerr.env` wird von nichts mehr erzeugt:** 510:252 referenziert `-${cfg.secrets.jellyseerrEnvFile}` (dank `-`-Präfix tolerant), aber die Erzeugerseite (alt: media-secrets/arr-provision) ist im neuen Modell nicht vorgesehen. Gleiches gilt für `usenetFile`/`vpnFile`/`indexersFile`: Es gibt außer dem defekten Portal (K5) keinen Schreiber, und **keinen Leser** — SABnzbd/WireGuard konsumieren diese Dateien nirgends. Das Secrets-Interface ist zur Hälfte Fassade.
- **M9 — `users.groups.media` wird an vier Stellen definiert** (510:173, 520 implizit via extraGroups, 530:37, 540:30, 550:58) — harmlos wegen Merge-Semantik, aber ein Kandidat für eine zentrale Definition im `default.nix`-`config`-Block.

---

## 6. Niedrige Findings / Nits

- `mkBlock`/`mkRepack` ignorieren ihren `trash_id`-Parameter (560:81–93) — aus dem Altstand geerbt, bei der Gelegenheit fixen (Parameter dient nur als Pseudo-Kommentar).
- `500-media-ingress/on-demand.nix` gehört namentlich/örtlich nicht unter „ingress" (s. H4.3).
- `secrets.arrApiKeyFile` als `types.path` mit String-Interpolation über `cfg.secrets.secretsDir` funktioniert, aber `types.path` + Laufzeit-erzeugte Dateien ist semantisch schief (kein Store-Pfad); `types.str` wäre ehrlicher (Altstand nutzte Strings).
- `network-cidrs.nix` (vendored) nimmt `config ? {}` entgegen und ignoriert es — totes Argument.
- `530-sabnzbd`: Kommentar „If persist is enabled, hook paths" stimmt nicht — der Eintrag ist unconditional (vgl. H3).
- Die alte SABnzbd-Assertion-Landschaft (media-Gruppe via `users.groups.media = { }` + gid-Pin) ist auf ein bloßes `media = { }` geschrumpft — konsistent mit H2, hier nur der Vollständigkeit halber.

---

## 7. Fähigkeits-Matrix Alt → Neu

| Fähigkeit | Alt (51–59, my.*) | Neu (500–591, grapefruitMedia.*) |
|---|---|---|
| Jellyfin tmpfs-Transcode + RAM-Cleanup | ✅ | ✅ unverändert |
| Config-Seeds (XML-Templating, idempotent) | ✅ | ✅ + metadataDir parametrisiert |
| *arr-Fabrik (User, Hardening, Memory) | ✅ arr-helper | ✅ inline in 520 (UID-Pins entfernt) |
| SSO / Forward-Auth vor allen UIs | ✅ Caddy+Pocket-ID | ❌ entfernt, `mode="sso"` No-Op (K2) |
| Ingress pro Dienst (dns-map, TLS) | ✅ | ⚠️ Stub: 3 Routen, kein TLS (H6) |
| Firewall geschlossen | ✅ | ❌ 13 Ports offen (K3) |
| Per-Service-API-Keys, deklarativ synchronisiert | ✅ arr-sync-keys | ❌ 1 Shared-Key, Env-Var wirkungslos (K4) |
| Download-Client-/Indexer-/Seerr-/Jellyfin-Provisionierung | ✅ 56-arr-sync | ❌ ersatzlos (H1) |
| On-Demand lidarr/readarr | ✅ Fabrik | ⚠️ dupliziert, tmpfiles-Bug (H4) |
| Usenet-VPN-Sandbox + Leak-Verify | ✅ | ✅ parametrisiert, aber ohne VPN-Gate/Alerting (H7) |
| Exportarr + Prometheus-Scrape | ✅ inkl. Auto-Enable | ⚠️ Exporter ja, Scrape/Keys nein (H5, K4) |
| Recyclarr TRaSH-Profile | ✅ | ✅ identisch, aber tote Optionen (M1) |
| Impermanence-Anbindung | ✅ my.impermanence | ❌ persist.* ohne Konsument (H3) |
| Feishin | — | ⚠️ neu, aber defekt (K6/K7) |
| Libreseerr | ✅ nativ (60-apps) | ❌ zusätzlich als :latest-Container (K6) |
| Secrets-Portal | — | ❌ neu, unauthentifiziert + defekt (K5) |
| Portabilität (fremdes NixOS-System) | ❌ my.*-verdrahtet | ✅ Kernziel erreicht (bei Fix der Blocker) |

---

## 8. Empfohlene Reihenfolge der Nacharbeiten

1. **Eval reparieren** (K1): Adapter `my.* → grapefruitMedia.*` oder konsequente Migration von rollout/server-map/media-secrets; `grapefruitMedia.enable` + `domain`/`storage`/`locale`/`hardware` für q958 setzen.
2. **Sicherheits-Baseline wiederherstellen** (K2, K3): Firewall-Block streichen; *arr auf 127.0.0.1 binden; `AUTH__METHOD=External` nur mit Assertion auf existierenden Auth-Proxy, sonst `Forms`.
3. **Secrets-Modell fixen** (K4, M8): per-Service-Keys, korrekte Env-Vars (`…__AUTH__APIKEY`) oder config.xml-Sync; Recyclarr/Exportarr daran anschließen.
4. **Prototypen entfernen oder fertigbauen** (K5, K6): Secrets-Portal raus (oder Auth + DynamicUser + writePython3Bin); Container-Module raus (natives libreseerr existiert; Feishin ggf. als statisches Frontend).
5. **On-Demand-tmpfiles-Bug** (H4.1) fixen, Duplikat in eine Funktion zurückfalten.
6. **Entscheidung dokumentieren**: 56-arr-sync-Provisionierung — bewusster Scope-Cut (dann ADR + arr-provision als Add-on-Layer) oder Portierung auf den neuen Namespace (H1).
7. Persist-Konsument anbinden oder Option entfernen (H3); Exportarr-Scrape-Bridge optional anbieten (H5); Ingress vervollständigen (H6); UID-Pin-Option (H2).

---

## 9. Schlusswort

Der Umbau zeigt zwei Handschriften: Der **übernommene Kern** (Jellyfin, Leak-Verify, Exportarr, Libs, Recyclarr-Profile) ist die reife, kommentierte, gehärtete Arbeit des Altstands — und die **Extraktions-Idee** mit `grapefruitMedia.*` als sauberer Modul-API ist ein echter Fortschritt. Die **neu geschriebenen Teile** (Firewall-Block, Secrets-Generator, Secrets-Portal, Container-Module, Ingress-Stub) fallen dagegen deutlich ab: unfertig, teils funktionsunfähig, und an drei Stellen sicherheitskritisch. Das Muster legt nahe, dass die neuen Komponenten ohne den Review-Standard entstanden sind, der den Rest des Repos prägt (ADRs, Assertions, Fail-Closed-Denken, POL-FT-Policies).

Mit den Punkten 1–4 aus Abschnitt 8 wäre das Modul ein legitimer, portabler Nachfolger. Ohne sie ist es ein Downgrade mit offenen Admin-Oberflächen.
