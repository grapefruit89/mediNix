# STATUS — Lagekarte mediNix

**Stand:** 2026-07-20
**Zweck:** Überblick behalten. Was steht, was wackelt, wo als Nächstes anfassen.

> Diese Datei ist der Einstiegspunkt, wenn man den Faden verloren hat.
> Sie ersetzt keine Issues — sie sagt, **in welcher Reihenfolge** man sie ansieht.

---

## ✅ Erledigt: der Stack ist evaluiert und gebaut

**Am 2026-07-20 zum ersten Mal auf echter Hardware gebaut — fehlerfrei.**

Ausgeführt auf q958 (NixOS 26.05, x86_64):

```
nix eval  .#nixosConfigurations.check.config.system.build.toplevel.drvPath   → OK
nix build .#nixosConfigurations.check.config.system.build.toplevel           → OK
  /nix/store/902sjrmb7jj8p0l5w2f423n283kinf1d-nixos-system-nixos-26.05…
```

**Null Fehler.** Weder Syntaxfehler noch falsche Optionspfade noch
Escaping-Probleme. Auch die beiden explizit als riskant markierten Stellen —
der `ddclient`-`sed`-Ausdruck und die Recyclarr-YAML-Strukturen — sind
durchgelaufen. Caddy wird korrekt in die Closure gezogen, der Ingress ist also
verdrahtet.

Möglich wurde das durch den neuen `flake.nix` samt `checks/minimal-host.nix`
(vorher gab es keinen Einstiegspunkt, über den das Modul allein evaluierbar
gewesen wäre — das war Issue #11).

Einzige Ausgabe war eine **beabsichtigte** Warnung:

```
[50-media/arr-stack] Kein Forward-Auth-Proxy deklariert
(grapefruitMedia.authProxyPresent = false) -- *arr-Apps laufen mit
AUTH__METHOD=Forms (lokaler Login).
```

### Was das **nicht** heißt

Gebaut ≠ funktionsfähig. Bewiesen ist: der Nix-Code ist syntaktisch und
typmäßig korrekt und erzeugt eine vollständige System-Closure. **Nicht**
bewiesen ist, dass die Dienste starten, sich gegenseitig erreichen oder die
provisionierten API-Aufrufe stimmen. Die in Abschnitt „Was wackelt" markierten
ungeprüften Daten (trash_ids, Katalog-Hostnamen, vier API-Endpunkte) sind
weiterhin ungeprüft — ein Build fasst sie nicht an.

### 🔴 Konkrete Stolperfalle beim nächsten Rebuild auf q958

`vpn.dns` ist jetzt **fail-closed** (Default `[ ]` + Assertion). Wenn
`usenet-confinement` aktiv ist und `my.services.privado-vpn.dns` nicht gesetzt
ist, **bricht der Build** — mit klarer Meldung. Das ist Absicht, soll aber nicht
überraschen.

---

## ✅ Was steht

| Bereich | Stand |
|---------|-------|
| **Portabilität** | Kein `my.*` im Kern, alles über Optionen, Libs vendored |
| **DNS/Ingress** | Drei Pfade (WAN-DDNS / LAN-DDNS / mDNS), `.local` auth-frei, Doppel-Matcher |
| **Provisionierung** | `525-provision/` portiert, Opt-in, kein Host-Hardcoding |
| **Härtung** | Factory-Profile inkl. `node`, fail-closed VPN-DNS, Loopback-Bind |
| **Paket-Overrides** | `package`-Option für alle elf Dienste |
| **Dokumentation** | AGENTS.md, network-topology, api-reference, vier ADRs |
| **Backup** | mediNix-Repo ist deckungsgleich mit dem lokalen Stand |

---

## 🟡 Was wackelt

| # | Problem | Konsequenz |
|---|---------|------------|
| 1 | **Nix-Grok auf GitHub ist veraltet** — dort liegt noch die alte flache `50-media`-Struktur. Der Refactor wurde nie dorthin committet. | Zwei divergierende Wahrheiten. Der alte Stand enthält aber die **einzige veröffentlichte Kopie** von `56-arr-sync/` und `arr-helper.nix` — nicht löschen, bevor gesichert. |
| 2 | **Lokaler Nix-Grok-Tree ist CRLF-verseucht** — praktisch jede Datei gilt als geändert. | Ein Commit dort erfordert erst eine Zeilenenden-Bereinigung, sonst 369 Dateien Rauschen. |
| 3 | **Halb migrierter Refactor**: `lib/provision-unit.nix` existiert, aber nur `keys.nix` nutzt ihn. Die anderen sieben haben noch den alten Block. | Inkonsistent, aber **funktional identisch** — beide Formen erzeugen dieselbe Unit. Kein Defekt, nur unfertig. |
| 4 | **ADR-5036 und ADR-5037 sind Entwürfe** — `preferences.profiles` existiert noch nicht, Recyclarr hat weiterhin 40 hartkodierte Blöcke. | Die Glühbirnen-API ist entworfen, nicht gebaut. |
| 5 | **Ungeprüfte Daten an mehreren Stellen** — trash_ids, Katalog-Hostnamen, vier API-Endpunkte, SABnzbd-`connections`-Default. | Alle sind **markiert** (⚠️), aber keine ist verifiziert. Nichts davon blind übernehmen. |
| 6 | **Offene Frage: API-Key auf zwei Wegen** — per `EnvironmentFile` *und* per `config.xml`-Injektion. | Möglicherweise ist ein Weg überflüssig; das spart einen Restart-Zyklus. Testverfahren steht in `docs/api-reference.md`. |

---

## 🔨 Wo als Nächstes Hand anlegen

Nach Risiko × Nutzen, nicht nach Bequemlichkeit:

### 1. ~~Dry-Build auf echtem System~~ — **erledigt 2026-07-20**
Durchgelaufen, null Fehler. Siehe oben. Damit ist die Blockade weg, die alles
andere aufgehalten hat. `flake.nix` + `checks/` liegen jetzt im Repo, der Test
ist jederzeit wiederholbar:

```
nix build .#nixosConfigurations.check.config.system.build.toplevel
```

**Neuer wichtigster Schritt:** ein `nixosTest` (Issue #48), der die Dienste
tatsächlich startet. Der Build beweist Syntax, nicht Funktion.

### 2. `#12` — vhostMap im Ingress verdrahten
Die DNS-Ableitung (`lib/dns.nix`) kennt Hostname-Overrides (`navidrome → music`),
der Ingress baut aber weiterhin `${name}.${domain}`. **Eine halbe SSoT ist
schlimmer als keine**: DNS-Record und vHost zeigen auf verschiedene Namen.

### 3. Provision-Refactor zu Ende bringen (7 Dateien)
Mechanisch, `keys.nix` ist die Vorlage. Zahlt direkt auf die geplante Härtung ein.

### 4. `#11` Flake + `#18` GPU — die Türsteher für Fremdnutzer
Ohne `flake.nix` kann niemand das Modul einbinden. Ohne GPU-Abstraktion scheitert
jeder ohne Intel-iGPU. Beides blockiert den eigentlichen Zweck des Repos.

### 5. ADR-5036/5037 umsetzen
Erst danach, weil beide auf einer geprüften Basis aufbauen sollten.

---

## Wo was steht

| Frage | Datei |
|-------|-------|
| Regeln für Agenten (Regel 0: Originalquellen!) | `AGENTS.md` |
| Naming/DNS/Ingress-Zielzustand | `grok-review.md` |
| Wer erreicht was, von wo | `docs/network-topology.md` |
| API-Endpunkte + Verifikationsstand | `docs/api-reference.md` |
| Provisionierungs-Treiber (Entwurf) | `docs/adr/5035-…` |
| Glühbirnen-API (Entwurf) | `docs/adr/5036-…` |
| Daten statt Code (Entwurf) | `docs/adr/5037-…` |
| Tier-Zuordnung (SSoT) | `lib/service-tiers.nix` |
| Alle Optionen | `default.nix` |

**Issues:** 21 Stück, davon 6 geschlossen. Zwei Epics: #10 (Härtung), #20 (Portabilität).
**Discussions:** 22, englisch, eine je Issue — für die Zusammenarbeit mit externen Mitlesenden.
