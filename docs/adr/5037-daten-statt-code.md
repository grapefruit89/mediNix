# ADR-5037 — Daten statt Code: Kataloge und Regeln statt Wiederholung

**Status:** accepted (Entwurf, noch nicht gebaut)
**Datum:** 2026-07-18
**Betrifft:** `560-recyclarr/`, `525-provision/`, `lib/`
**Verwandt:** ADR-5036 (Glühbirnen-API), ADR-5035 (Treiber-Architektur)

---

## Das gemeinsame Muster

Zwei Stellen im Modul sehen unterschiedlich aus, haben aber dieselbe Ursache:

| Stelle | Symptom | Ursache |
|--------|---------|---------|
| `560-recyclarr/default.nix` | 442 Zeilen, 40 handgeschriebene `assign_scores_to`-Blöcke, zwei fest verdrahtete Profilnamen | **Daten stehen im Code** |
| `525-provision/*.nix` | derselbe `serviceConfig`-Block in acht Dateien | **Wiederholung statt Regel** |

Beides ist dieselbe Krankheit: *Was sich wiederholt oder variiert, ist als
Literal ausgeschrieben statt als Datenstruktur plus Regel ausgedrückt.*

Und beides wird durch geplante Arbeit **schlimmer**, nicht besser:

- ADR-5036 generiert Profile aus `preferences.profiles` → n Profile × 2 Apps ×
  Sprach-Gates × Qualitätsketten. Bei zwei Profilen sind das schon 4 Profile mit
  je ~10 Format-Zuweisungen. Handgeschrieben nicht mehr pflegbar.
- Die Härtung der Provisionierungs-Units (#49-Follow-up) müsste heute an acht
  Stellen erfolgen — mit der Gefahr, eine zu vergessen.

**Leitsatz:** Daten in Tabellen, Verhalten in Regeln, Wiederholung in Helfer.

---

## Teil 1 — Recyclarr: Katalog + Rolle statt 40 Score-Blöcke

### Das Problem konkret

Heute steht 40× sinngemäß dies im Code:

```nix
{
  trash_ids = [ "86bc3115eb4e9873ac96904a4a68e19e" ];
  assign_scores_to = [ { name = "German 1080p HEVC"; score = 10000; } ];
}
```

Der Profilname ist ein Literal. Der Score ist ein Literal. Die `trash_id` ist ein
nackter Hash ohne Herkunftsangabe. Bei einem zweiten Profil verdoppelt sich alles.

### Die Lösung: `role` statt Score

Der entscheidende Schritt ist, **den Score nicht zu speichern, sondern
abzuleiten**. Jedes Custom Format bekommt eine *Rolle*; der Score ergibt sich aus
Rolle + `languageMode`.

```nix

> **Hinweis (2026-07-21):** Die unten beschriebenen Dateien unter `lib/`
> (`recyclarr-formats.nix`, `recyclarr-scoring.nix`, `ingress-lib.nix`,
> `usenet-catalog.nix`) sind **NOCH NICHT UMGESETZT**. Dieses ADR beschreibt
> einen Entwurf, kein vorhandenes Verzeichnis — wer die Dateien sucht, findet
> sie nicht, und das ist kein Fehler.

# lib/recyclarr-formats.nix  -- reine DATEN, kein Verhalten
{
  german = {
    id = "86bc3115eb4e9873ac96904a4a68e19e";
    kind = "language"; lang = "de"; role = "target";
    source = "TRaSH-Guides docs/json/radarr/cf/german.json";
    verified = null;              # ⚠️ Datum eintragen, sobald geprüft
  };
  germanDL = {
    id = "f845be10da4f442654c13e1f2c3d6cd5";
    kind = "language"; lang = "de"; role = "target-preferred";
    source = "…"; verified = null;
  };
  notGerman = {
    id = "…";
    kind = "language"; lang = "de"; role = "exclude";
    source = "…"; verified = null;
  };
  x265 = { id = "…"; kind = "codec"; role = "bonus"; score = 500; source = "…"; verified = null; };
  lq   = { id = "…"; kind = "quality"; role = "block";  source = "…"; verified = null; };
}
```

### Die Regel

```nix
# lib/recyclarr-scoring.nix  -- reines VERHALTEN, keine Daten
scoreFor = { role, mode }:
  if role == "target-preferred" then 11000
  else if role == "target"      then 10000
  else if role == "exclude"     then (if mode == "required" then (-1000000) else (-10000))
  else if role == "block"       then (-35000)
  else if role == "bonus"       then null      # Score steht am Format selbst
  else 0;
```

Damit wird aus 40 handgeschriebenen Blöcken **eine Schleife**:

```
für jedes Profil aus preferences.profiles:
  Zielformate  = Formate mit role ∈ {target, target-preferred} und lang ∈ profile.languages
  Ausschlüsse  = Formate mit role = exclude und lang ∈ profile.languages
  Blocker      = Formate mit role = block         (immer)
  Boni         = Formate mit role = bonus         (immer)
  → assign_scores_to = scoreFor(role, profile.mode)
```

**Was das löst:**

- Ein neues Profil kostet **null** neue Format-Blöcke.
- Eine Score-Änderung (z.B. `-1000000` → `-999999`) erfolgt an **einer** Stelle.
- `verified`-Feld erzwingt die Herkunftspflicht aus AGENTS.md Regel 0. Ein
  Eintrag ohne Datum ist sichtbar ungeprüft — statt unsichtbar geraten.
- Der Katalog ist eine **Tabelle**, die man lesen kann, ohne Nix zu verstehen.

### Neue Dateistruktur

```
560-recyclarr/
├── default.nix              # Optionen + services.recyclarr  (dünn)
├── profiles.nix             # Profil-Generierung aus preferences
└── quality-defs.nix         # Qualitätsdefinitionen je Auflösung

lib/
├── recyclarr-formats.nix    # DATEN: trash_id-Katalog mit Rolle + Herkunft
└── recyclarr-scoring.nix    # REGEL: Rolle + Modus → Score
```

Warum die beiden `lib/`-Dateien nicht in `560-recyclarr/` liegen: Sie sind reine
Daten bzw. reine Funktionen ohne Modul-Charakter — genau wie `service-tiers.nix`
und `dns.nix`. Das hält die Trennung zwischen *Modul* (setzt `config`) und
*Bibliothek* (liefert Werte) sauber.

### ⚠ Migrationsregel

Beim Verschieben der 40 IDs in den Katalog wird **keine ID abgetippt oder aus dem
Gedächtnis ergänzt**. Jede kommt per Copy-Paste aus der bestehenden Datei, und
`source`/`verified` werden nachgezogen, sobald jemand sie gegen TRaSH prüft.
Ein Zahlendreher in einem Hash ist unsichtbar und führt dazu, dass das Format
still nicht greift.

---

## Teil 2 — Provisionierung: ein Unit-Helfer

### Das Problem konkret

In allen acht Task-Dateien steht identisch:

```nix
serviceConfig = {
  Type = "oneshot";
  RemainAfterExit = true;
  User = "root";
  Restart = "on-failure";
  RestartSec = "30s";
  StartLimitBurst = 3;
};
```

Das ist keine Korrektheitsfrage — es funktioniert. Es ist eine **Wartungsfalle**:
Die geplante Härtung dieser Units (#49) müsste acht Dateien anfassen.

### Die Lösung

```nix
# lib/provision-unit.nix
{ lib }:
{
  mkProvisionUnit =
    { name, description, after ? [ ], wants ? [ ], environment, script
    , restartSec ? "30s", startLimitBurst ? 3, wantedBy ? [ "multi-user.target" ]
    }:
    {
      systemd.services.${name} = {
        inherit description after wants wantedBy environment script;
        startLimitIntervalSec = 600;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Root: schreibt in die App-Configs und startet Units neu.
          # HIER wird künftig gehärtet -- eine Stelle für alle acht Units.
          User = "root";
          Restart = "on-failure";
          RestartSec = restartSec;
          StartLimitBurst = startLimitBurst;
        };
      };
    };
}
```

Jede Task-Datei schrumpft dann auf das, was sie **wirklich** unterscheidet:

```nix
config = lib.mkIf active (provisionLib.mkProvisionUnit {
  name = "arr-sync-keys";
  description = "Provision: apply declarative *arr/SABnzbd API keys";
  after = svcDep; wants = svcDep;
  environment = { … };
  script = lib.getExe arrProvision.arrKeysSync;
});
```

**Gewinn:** ~15 Zeilen weniger pro Datei, und die Härtungs-Policy wird zu einer
Ein-Zeilen-Änderung statt zu acht.

---

## Umsetzungsreihenfolge

| # | Schritt | Abhängigkeit | Risiko |
|---|---------|--------------|--------|
| 1 | `lib/provision-unit.nix` + 8 Tasks umstellen | keine | niedrig — reiner Refactor, identisches Ergebnis |
| 2 | `lib/recyclarr-formats.nix` anlegen, 40 IDs per Copy-Paste umziehen | keine | niedrig, aber **sorgfältig** (siehe Migrationsregel) |
| 3 | `lib/recyclarr-scoring.nix` + `profiles.nix` | Schritt 2 | mittel — hier entsteht die Generierung |
| 4 | `quality-defs.nix` aus `preferences.quality` | Schritt 3 | mittel |
| 5 | `default.nix` auf die neuen Teile reduzieren | 2–4 | niedrig |

**Schritt 1 und 2 sind unabhängig voneinander** und können sofort passieren.
Schritt 3–5 gehören inhaltlich zu ADR-5036 und sollten zusammen mit der
`preferences`-Option umgesetzt werden — sonst baut man die Generierung gegen eine
Schnittstelle, die es noch nicht gibt.

---

## Konsequenzen

**Positiv**
- Ein neues Sprachprofil kostet keine neuen Format-Blöcke, nur einen Listeneintrag.
- Score-Politik und Härtungs-Politik sind je **eine** Stelle.
- Der Format-Katalog wird als Tabelle lesbar und prüfbar — inklusive sichtbarer
  Kennzeichnung ungeprüfter Einträge.

**Negativ**
- Eine Indirektionsebene mehr: Wer einen Score sucht, findet ihn nicht mehr direkt
  am Format, sondern in der Regel. Das muss dokumentiert sein, sonst sucht jemand.
- Die Rollen-Systematik (`target` / `exclude` / `block` / `bonus`) ist eine
  Erfindung dieses Moduls, kein TRaSH-Konzept. Wer TRaSH kennt, muss sie erst lernen.

**Bewusst nicht gelöst**
- `500-media-ingress/default.nix` (375 Zeilen) bleibt vorerst. Die Teile dort
  teilen sich einen großen `let`-Block; eine Aufteilung erzwingt eine
  `lib/ingress-lib.nix` mit Funktionen. Das lohnt erst, wenn ohnehin jemand dort
  arbeitet — etwa bei #12 (vhostMap verdrahten) oder dem LAN-Alias.
