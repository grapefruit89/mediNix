# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Herstellerunabhaengige Hardwarebeschleunigung — leitet Geraete, Pakete und ffmpeg-Methode aus einer einzigen Option ab
#   docs:
#     - docs/adr/5041-gpu-herstellerabstraktion.md
#   tags: [gpu, vaapi, nvenc, qsv, transcode]
# ---
#
# PROBLEM, das das hier loest:
# Bis 2026-07-20 war das Modul auf Intel festgenagelt -- renderD128 als fester
# Default, vpl-gpu-rt (Intel-only) im Paketpfad, VAAPI hart in der
# Jellyfin-Konfiguration. Wer mit einer NVIDIA-Karte kam, bekam keine
# Beschleunigung und keine brauchbare Fehlermeldung: DeviceAllow gab /dev/dri
# frei, die NVIDIA-Knoten fehlten, und ffmpeg fiel still auf die CPU zurueck.
#
# Gleiche Fehlerklasse wie mkForce in der service-factory: eine Annahme ueber
# die Umgebung, hart verdrahtet.
#
# LOESUNG: eine Option, aus der alles Weitere abgeleitet wird.
{ lib, pkgs }:
let
  # Was jeder Hersteller braucht -- an EINER Stelle, nicht ueber vier Module verteilt.
  vendors = {

    # ── Intel (Gen 8+ bis Arc/Battlemage) ────────────────────────────────────
    intel = {
      description = "Intel QuickSync über VAAPI";
      # ffmpeg-Methode, wie Jellyfin sie in encoding.xml erwartet
      hwaccel = "vaapi";
      # Geraeteknoten, die die Unit sehen darf
      devices = [
        "/dev/dri"
        "/dev/dri/card0"
        "/dev/dri/renderD128"
      ];
      # Der Pfad, den ffmpeg als VAAPI-Geraet bekommt
      renderDevice = "/dev/dri/renderD128";
      # Laufzeitpakete. intel-media-driver deckt Gen8+ inkl. Arc/B-Serie ab;
      # vpl-gpu-rt ist die neuere oneVPL-Laufzeit fuer Arc und Xe.
      packages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
        libva-utils
      ];
      # Gruppen, die der Dienst braucht
      groups = [
        "video"
        "render"
      ];
    };

    # ── AMD (GCN und neuer) ──────────────────────────────────────────────────
    amd = {
      description = "AMD über VAAPI (Mesa)";
      hwaccel = "vaapi";
      devices = [
        "/dev/dri"
        "/dev/dri/card0"
        "/dev/dri/renderD128"
      ];
      renderDevice = "/dev/dri/renderD128";
      # Mesa bringt den VAAPI-Treiber mit; kein proprietaeres Paket noetig.
      packages = with pkgs; [
        mesa
        libva-utils
      ];
      groups = [
        "video"
        "render"
      ];
    };

    # ── NVIDIA ───────────────────────────────────────────────────────────────
    nvidia = {
      description = "NVIDIA NVENC/NVDEC";
      # NICHT vaapi: NVIDIA nutzt eine eigene ffmpeg-Schnittstelle.
      hwaccel = "nvenc";
      # Voellig andere Geraeteknoten als DRI -- genau hier ist das alte Modul
      # gescheitert.
      devices = [
        "/dev/nvidia0"
        "/dev/nvidiactl"
        "/dev/nvidia-modeset"
        "/dev/nvidia-uvm"
        "/dev/nvidia-uvm-tools"
      ];
      # NVIDIA kennt kein Render-Node im DRI-Sinn; ffmpeg waehlt per Index.
      renderDevice = "";
      packages = with pkgs; [
        nvidia-vaapi-driver
        libva-utils
      ];
      groups = [ "video" ];
    };

    # ── Keine Beschleunigung ─────────────────────────────────────────────────
    none = {
      description = "Software-Transkodierung (CPU)";
      hwaccel = "none";
      devices = [ ];
      renderDevice = "";
      packages = [ ];
      groups = [ ];
    };
  };

  # Erkennung fuer accel = "auto".
  #
  # EHRLICHE EINSCHRAENKUNG: Nix evaluiert rein -- wir koennen die Hardware zur
  # Bauzeit NICHT abfragen. "auto" wertet deshalb aus, was der Host bereits
  # ueber sich konfiguriert hat, nicht was physisch steckt. Das ist zuverlaessig,
  # weil wer eine NVIDIA-Karte nutzt, ohnehin den Treiber aktivieren muss.
  #
  # Reihenfolge bewusst: NVIDIA zuerst, weil ein System mit NVIDIA-Treiber
  # meist AUCH eine iGPU hat -- die dedizierte Karte ist dann die gewollte.
  detect =
    hostConfig:
    let
      hasNvidia =
        (hostConfig.hardware.nvidia.modesetting.enable or false)
        || (lib.elem "nvidia" (hostConfig.services.xserver.videoDrivers or [ ]))
        || (hostConfig.hardware.nvidia-container-toolkit.enable or false);
      hasGraphics = hostConfig.hardware.graphics.enable or false;
    in
    if hasNvidia then
      "nvidia"
    else if hasGraphics then
      "intel" # VAAPI-Pfad; AMD nutzt denselben
    else
      "none";

  resolve = accel: vendors.${accel} or vendors.none;
in
{
  inherit vendors detect resolve;

  # Die Auswahl, die default.nix als Option anbietet
  accelTypes = [
    "auto"
    "intel"
    "amd"
    "nvidia"
    "vaapi"
    "none"
  ];

  # "vaapi" ist ein Alias fuer den generischen VAAPI-Pfad (Intel ODER AMD),
  # fuer Leute, die es einfach halten wollen.
  normalize = accel: if accel == "vaapi" then "amd" else accel;
}
