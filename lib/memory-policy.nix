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

  mkServiceLimits =
    {
      oomScore ? null,
      memoryMax ? null,
      memoryHigh ? null,
      forceOom ? false,
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
      memoryMax = gb maxGB;
      memoryHigh = gb (high75 maxGB);
    };

  # ── Tier 1 — Ingress & Identität ────────────────────────────────────────────
  caddy =
    _:
    mkServiceLimits {
      memoryMax = "768M";
      memoryHigh = "512M";
    };

  pocketId =
    _:
    mkServiceLimits {
      oomScore = -900;
      forceOom = true;
      memoryMax = "256M";
      memoryHigh = "192M";
    };

  # ── Tier 3 — Observability ──────────────────────────────────────────────────
  loki =
    _:
    let
      maxGB = lib.max 1 (lib.floor (ramGB * 0.03));
      maxStr = if ramGB <= 16 then "768M" else gb maxGB;
      highStr = if ramGB <= 16 then "512M" else gb (high75 maxGB);
    in
    mkServiceLimits {
      oomScore = 300;
      memoryMax = maxStr;
      memoryHigh = highStr;
    };

  vector =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  grafana =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  # ── Tier 4 — *arr Stack ─────────────────────────────────────────────────────
  arr =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  audiobookshelf =
    _:
    mkServiceLimits {
      oomScore = 150;
      memoryMax = "1G";
      memoryHigh = "768M";
    };

  navidrome =
    _:
    mkServiceLimits {
      oomScore = 200;
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
