> **ABGELÖST:** Dieses Dokument (v1) wurde durch [`handoff-v2.md`](handoff-v2.md) ersetzt (Stand 2026-07-15).
> Phasen 0–5 sind dort definiert. Hier nur noch als Referenz für die ursprünglichen Block-Beschreibungen.

# Handoff: Umsetzung der Review-Findings (Blöcke 2–7)

**Basis:** `modules/50-media/claude-review.md` (NICHT verändern!)
**Stand:** 2026-07-15 — Block 1 ist umgesetzt (siehe unten). Dieses Dokument beschreibt die
restlichen Blöcke so, dass ein beliebiges Modell/Entwickler sie umsetzen kann.
Abschließendes Review erfolgt danach durch Claude.

## Für jeden Block gilt (Pflicht)

1. **Vorher lesen:** `claude-review.md` (das jeweilige Finding), `AGENTS.md`, `CLAUDE.md`.
2. **MCP-Pflicht:** Vor jedem `services.*`-Attribut / Paketnamen → nixos-MCP prüfen;
   vor jeder `lib.*`-Funktion → Noogle. Keine Annahmen aus Training.
3. **Gate:** Nach jeder Änderung auf q958: `sudo scripts/nixos-rebuild-safe.sh` (Dry-Build)
   muss grün sein, BEVOR committet wird. Kein `git push` ohne explizite Zustimmung von Mo.
4. **Nicht anfassen:** `claude-review.md`, `modules/50-media/compat-my.nix` nur erweitern,
   nicht umbauen. Stil: kein `with lib;` in neuen Dateien, `lib.` qualifizieren.

## Block 1 — ERLEDIGT (2026-07-15, Claude)

- `compat-my.nix` neu: Aliase `my.services.<svc>.enable → grapefruitMedia.<svc>.enable`
  (mkAliasOptionModule), SSoT-Mapping (ports/hardware/locale/storage/secrets/vpn/onDemand),
  UID/GID-Pins aus Registry (H2-Teilfix), `persist.extraPaths → my.impermanence.extraPaths`
  (H3-Fix), `ingress.enable = false` auf q958.
- Import in `machines/q958/default.nix` (Zeile 41).
- `rollout.nix`: `my.media.sync`-Block auskommentiert (TODO H1).
- `default.nix`: Firewall-Block entfernt (K3); neue Optionen `secrets.autoGenerate`
  und `secrets.portal.enable` (beide default false).
- `secrets-generator.nix` / `591-secrets-portal`: hinter diese Optionen gegated (K4/K5).
- **Offen aus Block 1:** Dry-Build auf q958 noch nicht gelaufen (kein Nix in dieser Umgebung).

## Block 2 — Security-Baseline (K2)

**Ziel:** Kein unauthentifizierter Zugriff möglich, egal welche Firewall-Stufe.

- [ ] In `520-arr-stack/default.nix`: Bind-Adresse der *arr-Apps explizit auf Loopback:
      `services.<name>.settings.server.bindaddress = "127.0.0.1";` — vorher per nixos-MCP
      prüfen, wie der Settings-Key im jeweiligen NixOS-Modul heißt (sonarr/radarr/readarr/
      prowlarr/lidarr; freeform settings → Sektion `server`, Key `bindaddress`).
- [ ] Assertion in `520`: `AUTH__METHOD=External` nur erlaubt, wenn ein Forward-Auth-Proxy
      existiert. Auf q958: `config.my.services.oauth2-proxy.enable`. Portabel: neue Option
      `grapefruitMedia.authProxyPresent` (bool, default false), Assertion darauf; compat-my.nix
      mappt sie auf `config.my.services.oauth2-proxy.enable or false`.
- [ ] Gleiches Muster für Jellyseerr/Navidrome prüfen (binden bereits an 127.0.0.1 — nur
      verifizieren, nichts ändern).

**Akzeptanz:** Dry-Build grün; `grep -r "AUTH__METHOD"` zeigt Assertion-Schutz;
kein Dienst bindet an 0.0.0.0.

## Block 3 — Secrets-Modell (K4, M8)

**Ziel:** Per-Service-Keys, wirksam injiziert; Recyclarr/Exportarr funktionsfähig.

- [ ] Env-Var-Name: `<SVC>__AUTH__APIKEY` statt `<SVC>__API_KEY` (Servarr-Konvention
      SECTION__KEY; vgl. bestehendes `SONARR__AUTH__METHOD`). Per Context7/GitHub-MCP
      verifizieren, ab welcher *arr-Version das honoriert wird.
- [ ] q958 nutzt bereits `machines/q958/media-secrets.nix` (per-Service-Keys unter
      `/var/lib/secrets/<svc>_api_key` + `<svc>.env`). Der Weg der Wahl: `secrets-generator`
      bleibt aus (Standalone-Feature), stattdessen prüfen, dass die vorhandenen env-Dateien
      den korrekten Env-Var-Namen enthalten — sonst dort fixen.
- [ ] Recyclarr (`560`): `api_key._secret` pro Dienst auf `/var/lib/secrets/<svc>_api_key`
      statt gemeinsames `arrApiKeyFile`. Portabel: neue Optionen
      `grapefruitMedia.secrets.<svc>ApiKeyFile` mit Default auf arrApiKeyFile.
- [ ] Exportarr (`570`): `apiKeyFile` pro Dienst analog.
- [ ] Falls `autoGenerate` behalten wird: pro Dienst eigenen Key generieren (Schleife),
      niemals bestehende Dateien überschreiben (`[ -f ] ||`).

**Akzeptanz:** Nach Switch auf q958: `curl -H "X-Api-Key: $(cat /var/lib/secrets/sonarr_api_key)"
http://127.0.0.1:5003/api/v3/system/status` → 200; Exportarr-Units aktiv statt ExecCondition-Skip.

## Block 4 — Prototypen (K5, K6, K7)

- [ ] `580-libreseerr/` **löschen** (Import aus `default.nix` entfernen) — natives Modul
      `modules/60-apps/62-libreseerr.nix` existiert und läuft.
- [ ] `551-feishin/` löschen ODER neu als natives statisches Frontend (Feishin ist eine SPA;
      Paket bauen + Caddy file_server). Kein OCI-Container (POL-FT-001, forbidden-tech.nix).
      Falls Container zwingend: podman-Backend, Unit heißt dann `podman-feishin`, SERVER_URL
      muss auf Host-IP zeigen (nicht 127.0.0.1 im Bridge-Netz), tmpfiles für Volume-Pfad.
- [ ] `591-secrets-portal/`: löschen oder auf `packages/secrets-portal` (Go, bereits im Repo,
      wird von `modules/20-security/2029-secrets-portal.nix` genutzt) umstellen. Nicht das
      Inline-Python behalten. Hinweis: q958 hat bereits `my.services.secrets-portal.enable = true`
      (machines/q958/default.nix ~Zeile 195) — Duplikat vermeiden.

**Akzeptanz:** `grep -r "oci-containers" modules/50-media` leer (oder podman-sauber);
Dry-Build grün; keine Unit-Referenzen auf `docker-*`.

## Block 5 — On-Demand-Fixes (H4)

- [ ] In `520-arr-stack/default.nix`: tmpfiles-Regeln (`metadataDir` + MediaCover) aus dem
      `(!onDemand)`-Zweig in einen eigenen, immer aktiven `mkIf (metadataDir != null)`-Zweig
      verschieben (Vorbild: alter arr-helper).
- [ ] `500-media-ingress/on-demand.nix`: lidarr/readarr-Duplikat in eine Funktion
      `mkArrOnDemand { name, publicPort, metadataDir, extraEnv }` zurückfalten
      (Vorbild: alte `58-arr-on-demand.nix` im Upload/Git-History). Env-Werte
      (UPDATE__BRANCH) aus `520` referenzieren statt duplizieren.
- [ ] Datei nach `520-arr-stack/on-demand.nix` verschieben (gehört nicht zu Ingress),
      Import in `default.nix` anpassen.

**Akzeptanz:** Dry-Build grün; kein doppelter LIDARR/READARR-Block mehr; tmpfiles auch bei
`onDemand.enable = true` vorhanden.

## Block 6 — Provisionierung (H1) — ENTSCHEIDUNG NÖTIG

Erst Mo fragen: portieren oder Scope-Cut?

**Falls portieren:** die 9 Dateien aus Git-History (`git show bfda319^:modules/50-media/56-arr-sync/...`
bzw. Upload-Datei) auf `grapefruitMedia.*` umziehen; `packages/arr-provision` bleibt Grundlage;
Optionen unter `grapefruitMedia.provision.*`; rollout.nix-TODO-Block (TreasureMaps) reaktivieren.
**Falls Scope-Cut:** ADR schreiben (docs/adr/, Template beachten), rollout-TODO-Block final
entfernen, README-Hinweis ins Modul.

## Block 7 — Ingress vervollständigen (H6) + DNS-Konzept

- [ ] Standalone-Modus: Site-Adresse `:80` (catch-all) statt `http://localhost:80`;
      pro aktiviertem Dienst ein `@matcher host <svc>.${domain}` + reverse_proxy.
- [ ] Global-Modus: vHosts für ALLE aktivierten Dienste generieren (map über Service-Liste),
      nicht nur 3 Stück. Auf q958 bleibt `ingress.enable = false` (fromSpec macht das).
- [ ] TLS: 443-Placeholder entfernen; Optionen `tls.mode = "off" | "internal" | "acme"`
      (internal = Caddy-interne CA). ACME gehört NICHT ins Modul (ADR-032: security.acme/lego
      auf Host-Ebene).
- [ ] DNS-Empfehlung (aus Diskussion 2026-07-15): KEIN `.local` (mDNS-Konflikt, RFC 6762).
      Eine kanonische Domain + Split-Horizon: intern Blocky-Rewrite auf LAN-IP, extern
      Cloudflare-DDNS; Wildcard-Cert via lego DNS-01. Kurznamen falls gewünscht über
      `.home.arpa` (RFC 8375).

## Kleinkram (M-Findings, bei Gelegenheit)

- `560`: tote Optionen `quality`/`primaryLanguage`/`secondaryLanguage` implementieren oder
  aus `default.nix` entfernen (M1). `mkBlock`/`mkRepack`: ungenutzten Parameter fixen.
- `lib/service-factory.nix`: tote Parameter (`mode`, `extraCaddy`, `caddyOnly`, `ipAllow`, …)
  entfernen oder implementieren (M2).
- Meta-YAML-Header in allen 5xx-Dateien nachtragen (M3), `with lib;` ersetzen (M4).
- `570`: mkExporter zusätzlich auf `cfgGlobal.enable` gaten (M6).
- `users.groups.media` zentral in `default.nix` definieren (M9).

## Bekannte Umgebungs-Falle für Agenten

Das Claude-Edit-Tool hat in dieser Windows-Cowork-Umgebung Dateien mit CRLF beschädigt
und am Ende abgeschnitten. Workaround: Dateien komplett per Shell-Heredoc/Python in der
Linux-Sandbox schreiben (`/sessions/.../mnt/Nix-Grok/...`), danach `file` + Klammer-Balance
prüfen. Auf q958 selbst (Claude Code nativ) besteht das Problem nicht.
