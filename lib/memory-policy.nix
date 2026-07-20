# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: systemd MemoryMax/MemoryHigh und OOMScoreAdjust pro Dienst-Tier
#   docs:
#     - docs/adr/003-oom-cgroup-isolation.md
#     - docs/memory_oom.md
#   tags:
#     - oom
#     - systemd
# ---
#
# Verwendung: import ./memory-policy.nix { inherit lib; ramGB = config.my.configs.hardware.ramGB; }
#
# RAM-adaptive Dienste leiten ihre Limits aus ramGB ab — damit skaliert die Konfiguration
# automatisch mit jeder Maschine.
# Feste Limits bleiben wo die Anwendung eine bekannte, maschinenunabhängige Obergrenze hat.
#
# Formel-Konvention (RAM-adaptive):
#   memoryMax  = floor(ramGB * Faktor), mit Mindestgrenze
#   memoryHigh = 75% von memoryMax (Kernel warnt ab hier, OOM-Kill erst ab max)
{
  lib,
  ramGB ? 16,
}:
let
  gb = n: "${toString n}G";
  mb = n: "${toString n}M";

  # Helper: berechnet MemoryHigh aus MemoryMax (75%, mindestens 1 GB)
  high75 = maxGB: lib.max 1 (lib.floor (maxGB * 0.75));

  # CPU kennt kein OOM: ein Prozess, der zu viel will, TOETET niemanden --
  # er verlangsamt die anderen. Deshalb kein Limit, sondern eine Gewichtung.
  #
  # CPUWeight (systemd-Default 100, Bereich 1-10000) wirkt NUR bei Konkurrenz.
  # Ist die Maschine langweilig, darf jeder Dienst alles nutzen -- im Gegensatz
  # zu CPUQuota, das auch im Leerlauf deckelt und damit Rechenzeit verschenkt.
  # Deshalb setzen wir bewusst CPUWeight und NICHT CPUQuota.
  #
  # Die Leiter spiegelt OOMScoreAdjust: wer beim Speichermangel zuletzt stirbt,
  # bekommt bei CPU-Konkurrenz am meisten. Begruendung ist dieselbe -- ein
  # stockender Film faellt sofort auf, ein langsamerer Download nicht.
  mkServiceLimits =
    {
      oomScore ? null,
      memoryMax ? null,
      memoryHigh ? null,
      forceOom ? false,
      cpuWeight ? null,
      ioWeight ? null,
    }:
    let
      oom =
        if oomScore != null then
          if forceOom then lib.mkForce oomScore else lib.mkDefault oomScore
        else
          null;
    in
    lib.filterAttrs (_: v: v != null) {
      OOMScoreAdjust = oom;
      MemoryMax = if memoryMax != null then lib.mkDefault memoryMax else null;
      MemoryHigh = if memoryHigh != null then lib.mkDefault memoryHigh else null;
      CPUWeight = if cpuWeight != null then lib.mkDefault cpuWeight else null;
      IOWeight = if ioWeight != null then lib.mkDefault ioWeight else null;
    };
in
{
  inherit mkServiceLimits gb mb;

  # ── Tier 1 — Datenbank ──────────────────────────────────────────────────────
  postgres =
    ramGB:
    mkServiceLimits {
      oomScore = -800;
      forceOom = true;
      cpuWeight = 300;   # Datenbank: blockiert sonst alles, was auf sie wartet
      ioWeight = 300;
      memoryMax = gb (lib.max 4 (lib.floor (ramGB * 0.3125)));
      memoryHigh = gb (lib.max 3 (lib.floor (ramGB * 0.25)));
    };

  # ── Tier 4 — Media ──────────────────────────────────────────────────────────
  # 20% des RAM für Jellyfin: Transcode-Puffer + Plugin-Overhead skalieren mit RAM.
  jellyfin =
    _:
    let
      maxGB = lib.max 2 (lib.floor (ramGB * 0.2));
    in
    mkServiceLimits {
      oomScore = 100;
      cpuWeight = 250;   # Transkodierung darf nicht ruckeln -- der Nutzer sieht es sofort
      ioWeight = 200;    # Lesen vom Medienspeicher waehrend der Wiedergabe
      memoryMax = gb maxGB;
      memoryHigh = gb (high75 maxGB);
    };

  # 6.25% des RAM für SABnzbd: Download-Puffer + Dekompression skalieren mit RAM.
  sabnzbd =
    _:
    let
      maxGB = lib.max 1 (lib.floor (ramGB * 0.0625));
    in
    mkServiceLimits {
      oomScore = 300;
      cpuWeight = 40;    # Entpacken/Reparieren darf warten -- niemand schaut zu
      ioWeight = 40;     # und es soll die Wiedergabe nicht ausbremsen
      memoryMax = gb maxGB;
      memoryHigh = gb (high75 maxGB);
    };

  # ── Tier 1 — Ingress & Identität ────────────────────────────────────────────
  caddy =
    _:
    mkServiceLimits {
      cpuWeight = 400;   # Reverse-Proxy: haengt er, haengt ALLES
      memoryMax = "768M";
      memoryHigh = "512M";
    };

  pocketId =
    _:
    mkServiceLimits {
      oomScore = -900;
      forceOom = true;
      cpuWeight = 300;   # Anmeldung blockiert sonst jeden Zugriff
      memoryMax = "256M";
      memoryHigh = "192M";
    };

  # ── Tier 3 — Observability ──────────────────────────────────────────────────
  # Observability darf im Zweifel warten -- Logs verlieren nur Aktualitaet,
  # keine Substanz.
  loki =
    _:
    let
      maxGB = lib.max 1 (lib.floor (ramGB * 0.03));
      maxStr = if ramGB <= 16 then "768M" else gb maxGB;
      highStr = if ramGB <= 16 then "512M" else gb (high75 maxGB);
    in
    mkServiceLimits {
      oomScore = 300;
      cpuWeight = 30;
      ioWeight = 30;
      memoryMax = maxStr;
      memoryHigh = highStr;
    };

  vector =
    _:
    mkServiceLimits {
      oomScore = 200;
      cpuWeight = 30;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  grafana =
    _:
    mkServiceLimits {
      oomScore = 200;
      cpuWeight = 50;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  # ── Tier 4 — *arr Stack ─────────────────────────────────────────────────────
  arr =
    _:
    mkServiceLimits {
      oomScore = 200;
      cpuWeight = 100;   # Standard -- Hintergrundsuche, keine Interaktion
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  audiobookshelf =
    _:
    mkServiceLimits {
      oomScore = 150;
      cpuWeight = 200;   # Streaming -- hoerbare Aussetzer bei Mangel
      memoryMax = "1G";
      memoryHigh = "768M";
    };

  navidrome =
    _:
    mkServiceLimits {
      oomScore = 200;
      cpuWeight = 200;   # Streaming, ggf. Transkodierung
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  # ── Tier 5 — Apps ───────────────────────────────────────────────────────────
  paperless =
    let
      maxGB = lib.max 2 (lib.floor (ramGB * 0.0625));
    in
    {
      slice = {
        MemoryMax = lib.mkDefault (gb maxGB);
        MemoryHigh = lib.mkDefault (gb (high75 maxGB));
      };
      service = mkServiceLimits {
        oomScore = 250;
      };
      sliceName = "system-paperless.slice";
    };
}
