# ---
# id: 5043
# title: "Dezimalrahmen — vier Anker, freie Mitte, fraktal über alle Ebenen"
# status: "accepted"
# note: "Umnummerierung beschlossen — Migration in Abschnitt 8"
# date: "2026-07-21"
# related: [5042, 5040]
# tags: ["numbering", "struktur", "isomorphie", "ordner", "konvention", "anker"]
# error_pattern: "dezimalrahmen|vier anker|_0|_2|_9|umnummerier|fundament|leitplanken"
# ---

# ADR-5043 — Der Dezimalrahmen für mediNix

Die projektübergreifende Regel steht in `devNIX/50-core/adr/8000-dezimalrahmen.md`. Dieses
ADR ist ihre **konkrete Anwendung auf mediNix** samt Migration.

## Das Problem

ADR-5042 machte Port, UID und Tier isomorph — aber die **Ordner-Präfixe** blieben
außen vor. Kein Präfix stimmte mit der Registry-Nummer überein (`510-jellyfin`
enthielt einen 541er-Dienst), und `jellyseerr` (551) wohnte versteckt im
`510-jellyfin/`-Ordner. Das ist nicht kaputt, aber irreführend — und es bricht
die fraktale Isomorphie, die über alle Projekte gelten soll.

## Die Entscheidung: vier Anker, überall gleich

```
_0  FUNDAMENT     Wissen der Domäne — CLAUDE.md, default.nix, docs, registry
_1  ZUGANG        wie kommt man rein — caddy, mDNS, ddns
_2  SICHERHEIT    wie geschützt — VPN-Confinement, Auth
_3…_8  DOMÄNEN    der mediNix-eigene Stoff, in Pipeline-Reihenfolge
_9  LEITPLANKEN   was alles einhält — Assertions
```

**`_0` ist Wissen, kein Code.** `50-core/` bekommt **keine** Dienst-`.nix`
— nur die `CLAUDE.md` der Domäne, das aggregierende `default.nix` (Options +
Auto-Import), `docs/`, `lib/` mit der `registry`. Die Dienste wohnen in 510–590.

## Die mediNix-Abbildung

| Dekade | Anker/Domäne | Dienste | Nummern |
|---|---|---|---|
| **50** | Fundament | Root: flake/default.nix, lib/, CLAUDE.md · `50-core/`: docs, ADRs, LEARNINGS, STATUS | — (kein Dienst) |
| **510** | Zugang | caddy, mDNS, ddns | 511, 512, 513 |
| **520** | Sicherheit | usenet-confinement | 521 |
| **530** | Beschaffung | prowlarr, sonarr, radarr, lidarr, readarr | 531–535 |
| **540** | Transfer | sabnzbd | 541 |
| **550** | Wiedergabe | jellyfin, audiobookshelf, navidrome, feishin | 551–554 |
| **560** | Anfragen | jellyseerr | 561 |
| **570** | Pflege | recyclarr, provision, exportarr ×4 | 571, 572, 573–576 |
| **590** | Leitplanken | lib/assertions | — |

`usenet-confinement` ist ein VPN-Mechanismus → `520-Sicherheit`, endlich am
richtigen Platz statt beim Downloader. `provision` erzeugt Laufzeit-Units →
`570-Pflege`, nicht Fundament. `jellyseerr` bekommt einen **eigenen** Ordner
(`561-anfragen/`), heute liegt es irreführend bei Jellyfin.

## Die volle Umnummerierung

Beschlossen: **voll**, nicht nur Ordner umbenennen. Sonst bliebe die
Inkonsistenz halb bestehen. Alte → neue Nummer (Port = Nummer × 10):

| Dienst | alt | neu | Port alt → neu |
|---|---|---|---|
| caddy | 501 | 511 | 5010 → 5110 |
| usenet-confinement | 591 | 521 | — |
| prowlarr | 511 | 531 | 5110 → 5310 |
| sonarr | 512 | 532 | 5120 → 5320 |
| radarr | 513 | 533 | 5130 → 5330 |
| lidarr | 514 | 534 | 5140 → 5340 |
| readarr | 515 | 535 | 5150 → 5350 |
| sabnzbd | 521 | 541 | 5210 → 5410 |
| jellyfin | 541 | 551 | 5410 → 5510 |
| audiobookshelf | 542 | 552 | 5420 → 5520 |
| navidrome | 543 | 553 | 5430 → 5530 |
| feishin | 544 | 554 | — (statisch) |
| jellyseerr | 551 | 561 | 5510 → 5610 |
| recyclarr | 531 | 571 | — (Timer) |
| exportarr ×4 | 561–564 | 573–576 | 5610… → 5730… |

**Kein Dienst behält seine Nummer.** Das ist der Preis der vollen Isomorphie —
jetzt in der Entwicklungsphase billig (keine Nutzer, keine Daten), später teuer.
Genau die Lehre aus ADR-5042.

## Ordner-Umbenennungen

| Jetzt | Wird |
|---|---|
| *(Wurzel: default.nix, lib/, docs/)* | `50-core/` |
| `500-media-ingress/` | `510-zugang/` |
| `590-usenet-confinement/` | `520-sicherheit/` |
| `520-arr-stack/` | `530-beschaffung/` |
| `530-sabnzbd/` | `540-transfer/` |
| `510-jellyfin/` | `550-wiedergabe/` (+ jellyseerr raus) |
| `540-audiobookshelf/` | in `550-wiedergabe/` |
| `550-navidrome/` | in `550-wiedergabe/` |
| `544-feishin/` | in `550-wiedergabe/` |
| *(neu, aus jellyfin gelöst)* | `561-anfragen/` |
| `560-recyclarr/` + `525-provision/` + `570-exportarr/` | `570-pflege/` |

Playback-Dienste wandern in **einen** `550-wiedergabe/`-Ordner (wie schon
`530-beschaffung` alle *arr in einem hält). Das ist die bestehende Fabrik-Logik,
nicht ihr Bruch.

## Verschachtelung — adoptiert (2026-07-22)

- **Zweistellige Dekaden-Ordner (`5N-name/`), Dienste als `5NN`-Dateien darin.**
  Jedes Dekaden-`default.nix` ist die `5N0`-Block-ID und importiert rekursiv seine
  `5NN`-Dienste. Der frühere Einwand („flacher Import bräche") ist gelöst: der
  Auto-Import ist jetzt zweistufig. Fabrik-Dekaden (`53-beschaffung`,
  `57-pflege/572-provision`) bleiben Ordner. UID = Port = Nummer × 10.
- **Unit-Namen, State-Pfade, DNS bleiben sprechend** (ADR-5042): `jellyfin.service`,
  `/var/lib/jellyfin`, `jellyfin.local`. Nur die *Ordner-* und *Registry-Nummer*
  ändert sich, nicht die nixpkgs-verdrahteten Namen.

## Konsequenzen

**Leichter:** Ordner = Registry-Nummer = Port-Basis, eine Zahl überall. Vier
Anker in jedem Projekt wiedererkennbar. Die Dekade verrät die Pipeline-Stufe.

**Schwerer:** Jeder Port ändert sich → Rebuild + Verify aller elf Dienste.
Referenzen in Docs/Kommentaren nachziehen. `525-provision` löst sich in `570` auf.

**Ersetzt:** die Blockreihenfolge aus ADR-5042 (`500=ingress`). 5042 bleibt
gültig für Ableitungsregeln (Port/UID/GID), nur die Dekaden-Zuordnung ist neu.

## Migration — Reihenfolge

1. `lib/registry.nix`: neue Nummern eintragen. `nix eval …check` muss grün sein.
2. Ordner per `git mv` umbenennen; Dienste in Sammelordner zusammenführen.
3. Referenzen in Kommentaren/Docs nachziehen (`grep -rE '[0-9]{3}-'`).
4. `nixfmt · statix · deadnix · shellcheck` grün.
5. `setsid nohup … nixos-rebuild switch`, dann alle elf Dienste auf **neuen**
   Ports über `.local` prüfen.
6. `CLAUDE.local.md` Porttabelle aktualisieren.

## Nachweis (nach Umsetzung)

- Reine Ordner-Umbenennung ohne Nummernwechsel: Store-Pfad bitgleich.
- Nummernwechsel: alle elf Dienste antworten auf neuen Ports.
- `grep -rE 'media-[0-9]' docs/ *.md` ohne tote Referenzen.
