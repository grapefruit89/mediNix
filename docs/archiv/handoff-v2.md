> ## ⚠ ARCHIVIERT — nicht als Wahrheit lesen
>
> **Archiviert am 2026-07-21.** Dieses Dokument beschreibt einen Zielzustand
> oder Prüfstand von **vor** der Registry-Umstellung. Es kennt weder
> `lib/registry.nix` noch die abgeleiteten Ports (Nummer × 10) noch den
> Jellyfin-Seed-Fix.
>
> **Wo die Wahrheit heute steht:**
>
> | Frage | Datei |
> |---|---|
> | Port, UID, Tier, mDNS-Menge | `lib/registry.nix` |
> | Warum es so entschieden wurde | `docs/adr/` |
> | Was schiefging und warum | `LEARNINGS.md` |
> | Wie die Teile zusammenhängen | `docs/ARCHITEKTUR.md` |
> | Etwas ist kaputt | `docs/RUNBOOK.md` |
>
> **Warum es trotzdem hier liegt und nicht gelöscht wurde:** Code-Kommentare
> verweisen namentlich auf Befunde aus diesem Dokument (K2, K3, K4, H4.2 …).
> Wer diese Stellen versteht, braucht die Begründung. Gelöscht wäre die
> Begründung weg und die Kommentare unlesbar.
>
> **Was daraus noch gilt:** die *Begründungen* einzelner Befunde. **Was nicht
> mehr gilt:** jede Aussage der Form „dieses Dokument ist die SSoT für …".
> Diese Rolle hat die Registry übernommen.

---

# Handoff v2 — Umsetzungsplan Phasen 0–5 für modules/50-media (grapefruitMedia)

**Stand:** 2026-07-15, nach Umsetzung von Block 1 (Claude) und Blöcken 2/3/4/5 (Folge-Session).
**Basis-Dokumente:** `claude-review.md` (Findings K1–K7, H1–H7, M1–M9 — NICHT verändern!),
`claude-review-handoff.md` (v1, durch dieses Dokument abgelöst).
**Zweck:** Ein beliebiges Modell / ein Entwickler kann jede Phase eigenständig umsetzen.
Claude reviewt nach jeder Phase.

---

## 0. Ist-Stand (verifiziert 2026-07-15)

Bereits umgesetzt und im Working Tree vorhanden:

| Fix | Wo | Status |
|---|---|---|
| K1 Eval/Adapter | `compat-my.nix` + Import in `machines/q958/default.nix:41` + rollout-TODO | ✅ |
| K2 Bind + Auth-Fallback | `520-arr-stack/default.nix` (`bindaddress = 127.0.0.1`, `External`↔`Forms` je nach `authProxyPresent`) | ✅ mit Fehler (s. Phase 0.1) |
| K3 Firewall | Block aus `default.nix` entfernt | ✅ |
| K4 Secrets | per-Service-Keys, `<SVC>__AUTH__APIKEY`, idempotenter Generator (default aus), Recyclarr/Exportarr auf per-Service-Dateien | ✅ |
| K5/K6 Prototypen | 551/580/591 aus den Imports entfernt (Dateien liegen noch auf Platte) | ✅ teilweise (s. Phase 0.2) |
| H2 UID-Pins | compat-my.nix (Registry, mkForce) | ✅ (nur q958) |
| H3 persist | compat-my.nix → `my.impermanence.extraPaths` | ✅ (nur q958) |
| H4 On-Demand | `520-arr-stack/on-demand.nix` (mkArrOnDemand-Fabrik, tmpfiles-Fix) | ✅ |
| M6 Exporter-Gate | `570`: `cfgGlobal.enable` im Gate | ✅ |

Noch offen: H1 (Provisionierung), H5 (Scrape/Alerting), H6/H7 (Ingress, VPN-Gate),
M1–M5/M7–M9, sowie die Punkte in Phase 0. **Der Dry-Build auf q958 ist noch nie gelaufen.**

## Regeln für JEDE Phase (Pflicht)

1. `claude-review.md` niemals verändern. `compat-my.nix` nur erweitern.
2. **MCP-Pflicht** (CLAUDE.md): `services.*`-Optionen/Pakete → nixos-MCP; `lib.*` → Noogle;
   Caddy/Servarr-APIs → Context7; Fehlermeldungen externer Module → GitHub-MCP.
3. **Gate:** Auf q958 vor jedem Commit `sudo scripts/nixos-rebuild-safe.sh` (Dry-Build) grün.
   Kein `git push` ohne explizite Zustimmung von Mo.
4. Stil: kein `with lib;` in neuen/angefassten Dateien, Meta-YAML-Header nach Repo-Konvention,
   nixfmt-RFC-Formatierung.
5. **Umgebungs-Falle (Cowork/Windows):** Das Edit-Tool hat Dateien mit CRLF beschädigt und
   Enden abgeschnitten. In Cowork-Sessions Dateien IMMER komplett per Shell-Heredoc/Python in
   der Linux-Sandbox schreiben und danach `file <f>` + Klammer-Balance prüfen. In Claude Code
   nativ auf q958 besteht das Problem nicht.
6. Pro Phase ein Commit (Conventional-Commit-Stil, Verweis auf Finding-IDs).

---

## Phase 0 — Stabilisieren & Cleanup (≈ 30–45 min + Dry-Build-Iteration)

**Ziel:** Repo baut nachweislich; keine toten/gefährlichen Reste.

### 0.1 K2-Assertion → Warning (Fehler in der Block-2-Umsetzung)
`520-arr-stack/default.nix` (~Zeile 163–172): Die harte Assertion
`assertion = cfg.authProxyPresent` bricht die Eval für jeden Konsumenten ohne Auth-Proxy —
obwohl der Code den `Forms`-Fallback korrekt setzt (die Message sagt es selbst).

- [ ] `assertions = lib.optional cfg.enable { … }` ersetzen durch:
  ```nix
  warnings = lib.optional (cfg.enable && !cfg.authProxyPresent) ''
    [50-media/arr-stack] Kein Forward-Auth-Proxy deklariert (grapefruitMedia.authProxyPresent
    = false) -- *arr-Apps laufen mit AUTH__METHOD=Forms (lokaler Login). Fuer SSO:
    authProxyPresent = true setzen, wenn oauth2-proxy/Pocket-ID vor dem Ingress steht.
  '';
  ```
- [ ] Prüfen, ob `520-arr-stack/on-demand.nix` eine analoge Assertion hat → gleiches Muster.

### 0.2 Tote Dateien entfernen
- [ ] Verzeichnisse löschen: `551-feishin/`, `580-libreseerr/`, `591-secrets-portal/`
      (sind bereits aus den Imports raus; Inhalte bleiben über Git-History/Upload rekonstruierbar).
- [ ] Stub `500-media-ingress/on-demand.nix` (`{ ... }: { }` mit VERSCHOBEN-Kommentar) löschen.
- [ ] In `default.nix`: Optionen-Leichen entscheiden — `feishin.enable`, `libreseerr.enable`,
      `secrets.portal.enable`, `ports.feishin`, `ports.libreseerr`, `ports.secrets-portal`,
      `secrets.usenetFile/vpnFile/indexersFile` (kein Leser mehr, M8). Empfehlung: entfernen,
      solange nichts sie setzt (grep!). Falls Mo Feishin nativ will → Option behalten,
      Implementierung in Phase 5 als SPA + Caddy `file_server` (POL-FT-001: kein Docker).
- [ ] `claude-review-handoff.md` (v1) um Kopfzeile „abgelöst durch handoff-v2.md" ergänzen.

### 0.3 Dry-Build-Gate (kritischster Schritt)
- [ ] Auf q958: Repo-Stand hin (git pull / rsync), dann
      `sudo scripts/nixos-rebuild-safe.sh` — Fehler iterativ fixen. Erwartbare Kandidaten:
      Tippfehler in Alias-Pfaden, `services.seerr`-Existenz im nixpkgs-Pin,
      `mkAliasOptionModule`-Konflikte, Attributnamen in `my.ports`.
- [ ] Nach grünem Dry-Build: `nvd`-Diff ansehen — erwartete Änderungen: neue Env-Vars der
      *arr-Units, bindaddress, UID-Pins. KEINE unerwarteten Service-Removals.
- [ ] Vor dem echten `switch`: prüfen, dass `/var/lib/secrets/<svc>.env` die neuen
      `__AUTH__APIKEY`-Zeilen enthält (media-secrets.nix), sonst zuerst Phase-3-Teilcheck aus v1.

**Akzeptanz Phase 0:** Dry-Build grün; `find modules/50-media -name '*.nix' | wc -l` ohne
551/580/591; keine harte authProxy-Assertion; Commit erstellt.

---

## Phase 1 — Provisionierung zurückholen (H1) — der große Block (1–2 Sessions)

**Ziel:** Die deklarative 56-arr-sync-Suite des Altstands läuft wieder, als optionale
Schicht `grapefruitMedia.provision.*`, Backend = `packages/arr-provision` (existiert,
wird im Flake gebaut: `arr-provision = pkgs.callPackage ./packages/arr-provision { }`).

**Vorher Mo fragen:** portieren (dieser Plan) oder Scope-Cut per ADR. Empfehlung: portieren.

### 1.1 Quellen beschaffen
Alte Module liegen in der Git-History (vor dem Rewrite) bzw. im Upload:
`git log --all --oneline -- modules/50-media/56-arr-sync` → letzten Stand auschecken:
`git show <commit>:modules/50-media/56-arr-sync/<datei>.nix`.
Dateien: `keys.nix`, `settings.nix`, `download-clients.nix`, `prowlarr.nix`,
`jellyfin-sync.nix`, `seerr.nix`, `profiles.nix`, `locale.nix`, `default.nix`.

### 1.2 Zielstruktur
```
modules/50-media/525-provision/
  default.nix          # imports + options.grapefruitMedia.provision.{enable,…}
  keys.nix             # arr-sync-keys (API-Keys in config.xml + Restart)
  settings.nix         # TRaSH host settings
  download-clients.nix # SABnzbd-Registrierung in *arrs
  prowlarr.nix         # Indexer + App-Sync (syncLevel, indexers, backupIndexers)
  jellyfin.nix         # Admin-Bootstrap, Libraries, extraUsers, Intro-Scan
  seerr.nix            # Jellyseerr-Bootstrap
  profiles.nix         # Bulk-Profile-Zuweisung
  locale.nix           # Jellyfin/SABnzbd-Locale + Kategorien
```

### 1.3 Mechanische Portierungsregeln (pro Datei)
| Alt | Neu |
|---|---|
| `config.my.services.<svc>.enable` | `cfg.<svc>.enable` (cfg = config.grapefruitMedia) — Gate zusätzlich immer `cfg.enable && cfg.provision.enable` |
| `config.my.ports.<svc>` | `cfg.ports.<svc>` |
| `config.my.configs.locale.*` | `cfg.locale.*` |
| `/var/lib/secrets/<svc>_api_key` | `cfg.secrets.<svc>ApiKeyFile` |
| `/var/lib/secrets/sabnzbd_api_key` u. a. Nicht-Arr-Keys | neue Optionen `cfg.secrets.sabnzbdApiKeyFile`, `cfg.secrets.jellyseerrApiKeyFile`, `cfg.secrets.jellyfinAdminPasswordFile` (Defaults unter `secretsDir`) |
| `options.my.media.sync.<x>` | `options.grapefruitMedia.provision.<x>` (Strukturen 1:1 übernehmen: indexers/backupIndexers-Submodule, seerr-Optionen, extraUsers, …) |
| `arrProvision = pkgs.callPackage ../../../packages/arr-provision { }` | Pfadtiefe anpassen (`../../../` → je nach Ebene), oder besser: einmal in `525-provision/default.nix` via `_module.args` bereitstellen |
| `config.my.services.usenet-confinement.enable` (prowlarr VPN-Flag) | `cfg.usenet-confinement.enable` |

Auto-Enable-Muster des Altstands beibehalten (`my.media.sync.X.enable = mkDefault true` wenn
Grunddienste aktiv) → `provision.<x>.enable = lib.mkDefault …`, Master
`provision.enable = lib.mkEnableOption` (default false → Standalone-Nutzer opt-in).

### 1.4 systemd-Ketten unverändert übernehmen
Die after/wants-Ordnung des Altstands ist erprobt — exakt beibehalten:
`arr-sync-keys` → `arr-sync-settings` → `arr-sync-profiles` → `arr-sync-seerr`;
`arr-sync-jellyfin` nach jellyfin.service; alles `Type=oneshot`, `RemainAfterExit`,
`Restart=on-failure`, `startLimitIntervalSec` wie alt. Exportarr-`after` wieder auf
`arr-sync-keys.service` erweitern (aktuell: `arr-secrets-generator.service`).

### 1.5 Wiederanschluss q958
- [ ] `machines/q958/rollout.nix`: TODO-Block (TreasureMaps) reaktivieren, umbenannt auf
      `grapefruitMedia.provision.prowlarr.{indexers,backupIndexers}` — oder in compat-my.nix
      Aliase `my.media.sync.* → grapefruitMedia.provision.*` ergänzen und den Block
      original wiederherstellen (sauberer für die rollout-SSoT-Idee).
- [ ] compat-my.nix: `provision.enable = lib.mkDefault true;` für q958.

**Akzeptanz Phase 1:** Dry-Build grün. Nach Switch:
`systemctl status arr-sync-keys arr-sync-download-clients arr-sync-prowlarr` = exited/0;
in Sonarr-UI: SABnzbd als Download-Client sichtbar; Prowlarr: TreasureMaps-Indexer +
App-Registrierungen vorhanden; Seerr: initialisiert gegen Jellyfin.

---

## Phase 2 — Observability zurück (H5) (≈ 1 h)

**Ziel:** Exportarr wird wieder gescrapt; VPN-Leaks alarmieren wieder.

- [ ] **Scrape-Bridge (q958-seitig, in compat-my.nix):**
  ```nix
  # H5-Fix: Exportarr-Targets in VictoriaMetrics registrieren (wie Altstand 59-exportarr)
  services.victoriametrics.prometheusConfig.scrape_configs = lib.mkAfter (
    lib.flatten (lib.mapAttrsToList (svc: portName:
      lib.optional (gm.enable && gm.${svc}.enable && gm.exporters.enable) {
        job_name = "exportarr-${svc}";
        static_configs = [ { targets = [ "127.0.0.1:${toString gm.ports.${portName}}" ]; } ];
        scrape_interval = "30s";
      }) {
        sonarr = "exportarr-sonarr"; radarr = "exportarr-radarr";
        prowlarr = "exportarr-prowlarr"; lidarr = "exportarr-lidarr";
      })
  );
  ```
  Vorher per nixos-MCP prüfen: exakter Optionspfad `services.victoriametrics.prometheusConfig`
  im aktuellen Pin (Altstand nutzte ihn, sollte stimmen). lidarr nur bei `exporters.lidarr.enable`.
- [ ] **Auto-Enable wie alt:** in compat-my.nix
      `grapefruitMedia.exporters.enable = lib.mkDefault config.my.observability.victoriametrics.enable;`
- [ ] **Alerting-Hook (H7-Teil):** in `590-usenet-confinement/default.nix`:
      `systemd.services.usenet-vpn-verify.serviceConfig.OnFailure = lib.mkDefault [ "alerting-onfailure.service" ];`
      — aber nur wenn die Unit existiert. Portabel: Option
      `grapefruitMedia.vpn.onFailureUnit = mkOption { type = types.nullOr types.str; default = null; }`,
      compat-my.nix setzt sie auf `"alerting-onfailure.service"` (gated auf `config.my.alerting.enable`).
- [ ] **H7-Rest:** Assertion/Warning in 590, wenn `usenet-confinement.enable` aktiv ist, aber
      kein Interface provisioniert wird (q958: `config.my.services.privado-vpn.enable`; portabel:
      Warning „BindsTo=…device wartet ewig, wenn ${vpn.interface} nie erscheint").

**Akzeptanz:** Dry-Build grün; nach Switch `curl 127.0.0.1:8428/api/v1/targets` (bzw. VM-UI)
zeigt exportarr-Jobs als up; `systemctl cat usenet-vpn-verify` enthält OnFailure.

---

## Phase 3 — Ingress fertigbauen (H6) + DNS-Konzept (≈ 1 Session)

**Ziel:** Der Chamäleon-Ingress ist vollständig, TLS-fähig, auth-bewusst.
q958 behält `ingress.enable = false` (fromSpec-Ingress bleibt zuständig) —
diese Phase ist reine Standalone-Funktionalität, auf q958 nur Eval-neutral.

### 3.1 Routing
`500-media-ingress/default.nix` komplett neu strukturieren:
- [ ] Service-Liste zentral ableiten statt hardcoden:
  ```nix
  vhosts = lib.filterAttrs (_: v: v.enabled) {
    jellyfin  = { enabled = cfg.jellyfin.enable;  port = cfg.ports.jellyfin; };
    seerr     = { enabled = cfg.jellyseerr.enable; port = cfg.ports.jellyseerr; };
    sonarr    = { enabled = cfg.sonarr.enable;    port = cfg.ports.sonarr; };
    # … radarr readarr prowlarr sabnzbd audiobookshelf navidrome lidarr
  };
  ```
- [ ] **Standalone-Modus:** Site-Adresse `:80` (catch-all) statt `http://localhost:80`
      (Host-Header-Matching war der Bug — LAN-Clients matchen `localhost` nie).
      Pro Dienst `@<name> host <name>.${cfg.domain}` + `handle @<name> { reverse_proxy … }`.
      Den 443-„HTTPS OK"-Placeholder ersatzlos streichen.
- [ ] **Global-Modus:** `services.caddy.virtualHosts."<name>.${cfg.domain}"` per
      `lib.mapAttrs'` über dieselbe vhosts-Liste generieren.
      Caddy-Direktiven vorher via Context7 verifizieren.

### 3.2 Auth
- [ ] Neue Optionen: `ingress.auth.mode = "none" | "forward-auth"`,
      `ingress.auth.forwardAuthUrl = types.str` (z. B. oauth2-proxy `/oauth2/auth`).
      Bei `forward-auth`: `forward_auth`-Snippet in jeden vHost (außer Jellyfin-Ausnahme-Pfade
      für native Apps — Muster aus `lib/caddy-ingress.nix` des Repos übernehmen!).
- [ ] Kopplung: `authProxyPresent` bleibt die Wahrheit für die *arr-`AUTH__METHOD`;
      Assertion neu (jetzt korrekt): `ingress.auth.mode == "forward-auth" → authProxyPresent`.

### 3.3 TLS
- [ ] `ingress.tls.mode = "off" | "internal" | "custom"`:
      `internal` → Caddy `tls internal` (eigene CA, gut für reine LAN-Setups);
      `custom` → `ingress.tls.certFile/keyFile`-Optionen (konsumiert z. B. lego-Wildcard).
      ACME-Ausstellung selbst bleibt Host-Sache (ADR-032: security.acme/lego, NICHT Caddy-ACME).

### 3.4 DNS-Konzept (Doku, kein Code)
- [ ] `modules/50-media/README.md` Abschnitt „DNS & Namensschema":
      KEIN `.local` (mDNS-Kollision, RFC 6762). Empfohlen: eine kanonische Domain,
      Split-Horizon — intern Blocky/AdGuard-Rewrite `*.domain.de → LAN-IP`, extern
      Cloudflare-DDNS → WAN-IP; Wildcard-Cert `*.domain.de` via lego DNS-01;
      alternative interne Zone: `.home.arpa` (RFC 8375). Beispiel-Snippets für Blocky-Rewrite
      und security.acme-DNS-01 beilegen.

**Akzeptanz:** Dry-Build grün (q958, ingress aus). Zusätzlich lokaler Eval-Test einer
Minimal-Standalone-Config (siehe Phase 5 nixosTest) mit `ingress.mode = "standalone"`:
generiertes Caddyfile enthält alle aktiven Dienste; kein `http://localhost`-Site-Block mehr.

### Phase 3 Nacharbeit — 4 Bugs (gefunden + gefixt 2026-07-15)

Beim Code-Review nach dem Phase-3-Commit wurden vier Bugs in `500-media-ingress/default.nix`
gefunden und direkt behoben. Commit: "fix(ingress): 4 bugs Phase 3 Nacharbeit".

| # | Bug | Fix |
|---|-----|-----|
| 1 | `enabledServices`-Filter griff nie: `lib.optionalAttrs false {}` ergibt `{}`, nicht `null` — für jeden deaktivierten Dienst fehlte deshalb `svc.port` | `if enable then { port = ...; } else null` |
| 2 | `forward_auth`-Syntax falsch: Caddy erwartet `forward_auth <upstream> { uri <pfad>; }` — Upstream ohne Pfad | `forwardAuthUrl` aufgeteilt in `forwardAuthUpstream` (Adresse) + `forwardAuthUri` (Pfad, default `/oauth2/auth`) |
| 3 | `skipPaths` war No-Op: `skipPathsMatcher` definiert aber nirgends verwendet — native App-Clients wurden ausgesperrt | In `mkSvcBlock` verdrahtet: `@<name>Skip path` + zwei `handle`-Blöcke (skip direkt, Rest auth-gated) |
| 4 | `tls.mode = "custom"` hatte keinen `:443`-Block; `:80` redirectete bei aktivem TLS nicht | `:80` → `redir https://{host}{uri} 308`, `:443` für `internal` und `custom` |

Option-Umbenennung: `ingress.auth.forwardAuthUrl` (String mit Pfad) wurde durch
`ingress.auth.forwardAuthUpstream` + `ingress.auth.forwardAuthUri` ersetzt.
`README.md` + `default.nix` entsprechend aktualisiert.
Keine Konsumenten von `forwardAuthUrl` auf q958 (Ingress ist dort deaktiviert) — Breaking
Change ist sicher.

---

## Phase 4 — Hygiene / M-Findings (≈ ½ Session)

- [ ] **M1 Recyclarr-Optionen implementieren** (`560`): `quality` → Quality-Definition/-Gruppen
      parametrisieren (720p/1080p/4k-Größenlimits als Attrset, statt hardcoded
      `web1080pSizeLimits`); `primaryLanguage`/`secondaryLanguage` → die beiden Profile
      generisch bauen (`mkLangProfile primary secondary`), Scores wie gehabt
      (primär 10000er-Gate, sekundär 0er-Gate). `secondaryLanguage = "None"` → nur ein Profil.
      TRaSH-IDs bleiben sprachfix (German-CFs) — bei `primaryLanguage = "English"` schlicht
      Scores tauschen. Wenn zu aufwendig: Optionen ersatzlos streichen (ehrliche API).
- [ ] **M2 Factory entschlacken** (`lib/service-factory.nix`): ungenutzte Parameter
      (`mode`, `extraCaddy`, `caddyOnly`, `manageIngress`, `ipAllow`, `host`, `socketPath`,
      `upstreamHost`) entfernen; alle Aufrufer anpassen (grep `mode =` in 5xx-Dateien).
      Alternativ `mode` reaktivieren, falls Phase 3 die Factory fürs Ingress nutzt — dann
      dort entscheiden, nicht doppelt bauen.
- [ ] **M3 Meta-Header**: YAML-Header (layer/role/purpose/docs/tags) in alle 5xx-`default.nix`
      + `lib/network-cidrs.nix`; ADR-Verweise aus den Altdateien übernehmen
      (5031 usenet, 5033 on-demand, 003 OOM, 007 dendritic, 011 uid-schema).
- [ ] **M4 `with lib;` entfernen**: `default.nix`, `500-media-ingress/default.nix`,
      `520-arr-stack/secrets-generator.nix` (Rest prüfen: `grep -rn "with lib;" modules/50-media`).
- [ ] **M9 media-Gruppe zentral**: `users.groups.media = { gid = ? }` einmal in `default.nix`
      (`mkIf cfg.enable`), die vier Einzeldefinitionen (510/530/540/550) entfernen.
      q958: gid-Pin via compat (`gids.media`, falls in Registry — prüfen!).
- [ ] **Kleinkram**: `mkBlock`/`mkRepack` ungenutzten `trash_id`-Parameter fixen (560);
      totes `config ? {}`-Argument in `lib/network-cidrs.nix`; Kommentar in `530`
      („If persist is enabled…") an Realität anpassen; `secrets.arrApiKeyFile`-Typ
      `types.path` → `types.str` (Laufzeitpfade, keine Store-Pfade — alle *ApiKeyFile-Optionen).

**Akzeptanz:** Dry-Build grün; `grep -rn "with lib;" modules/50-media` leer;
statix/nixfmt sauber (Repo-Tooling: `statix.toml` vorhanden — `statix check modules/50-media`).

---

## Phase 5 — Portabilität ernten (≈ 1 Session)

- [ ] **Flake-Export:** in `flake.nix`:
  ```nix
  nixosModules.grapefruit-media = import ./modules/50-media;
  ```
  (Namenskonvention prüfen; compat-my.nix NICHT exportieren.)
- [ ] **nixosTest** (`modules/50-media/test.nix`, im Flake als `checks.x86_64-linux.media`):
      VM mit `grapefruitMedia = { enable = true; jellyfin.enable = true; sonarr.enable = true;
      secrets.autoGenerate = true; ingress = { enable = true; mode = "standalone"; }; }`.
      Testscript: warten auf `jellyfin.service`, `curl -f 127.0.0.1:5001/health`
      (Jellyfin-Health-Endpoint per Context7 verifizieren), `curl -f -H "X-Api-Key: $(cat
      /var/lib/media-secrets/sonarr_api_key)" 127.0.0.1:5003/api/v3/system/status`,
      Generator-Idempotenz (zweimal starten → Keys unverändert), Caddy `curl -H "Host:
      sonarr.grapefruit-media.local" 127.0.0.1:80`. GPU-/VA-API-Teile im Test deaktivieren
      (renderDevice-Assertion → im Test `hardware.renderDevice` auf Dummy + QuickSync aus,
      oder Assertion um `enableQuickSync`-Bedingung erweitern).
- [ ] **README** (`modules/50-media/README.md`): Quickstart (fremdes System),
      Optionen-Übersicht, Secrets-Modell (autoGenerate vs. extern/sops), DNS-Abschnitt
      (aus Phase 3.4), Grenzen (Provisionierung braucht arr-provision-Paket).
- [ ] **Feishin-Entscheidung** (falls Mo ja sagt): Paket `packages/feishin/` (SPA-Build via
      buildNpmPackage — Hash-Beschaffung beachten) + vHost im Ingress (`file_server`).
      Kein Container (POL-FT-001).
- [ ] Optional: `uidBase`-Option im portablen Modul (Review H2 sauber lösen statt nur via compat).

**Akzeptanz:** `nix flake check` (auf q958 oder Build-Host) grün inkl. Media-Test;
Modul in einer leeren VM-Config ohne my.*-Repo evaluierbar.

---

## Reihenfolge & Abhängigkeiten

```
Phase 0 ──► Phase 1 ──► Phase 2
   │                       
   └──────► Phase 3 ──► Phase 4 ──► Phase 5
```
Phase 0 blockiert alles (Dry-Build-Beweis). 1↔3 sind unabhängig voneinander.
Phase 5 zuletzt (Test deckt dann alles ab).

## Offene Entscheidungen für Mo

1. **Phase 1:** Provisionierung portieren (empfohlen) oder Scope-Cut + ADR?
2. **Phase 0.2/5:** Feishin nativ wiederbeleben oder streichen?
3. **Phase 4/M1:** Recyclarr-Sprachoptionen implementieren oder Optionen entfernen?
4. rollout.nix-Wiederanschluss der Provisionierung: via Alias (`my.media.sync.*`)
   oder direkt `grapefruitMedia.provision.*`? (Empfehlung: Alias — rollout bleibt SSoT-stilrein.)
