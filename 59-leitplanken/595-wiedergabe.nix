# 595 -- Leitplanken der Domaene 55-wiedergabe (Jellyfin, Audiobookshelf, GPU).
{ config, lib, ... }:
let
  cfg = config.grapefruitMedia;
in
{
  assertions = [
    # ══════════════════════════════════════════════════════════════════════════
    # L4 — Seccomp tötet statt abzulehnen
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !cfg.audiobookshelf.enable
        || (
          (config.systemd.services.audiobookshelf.serviceConfig.SystemCallFilter or null) == null
          || (config.systemd.services.audiobookshelf.serviceConfig.SystemCallErrorNumber or null) != null
        );
      message = ''
        [mediNix] audiobookshelf hat einen SystemCallFilter, aber kein
        SystemCallErrorNumber.

        WAS PASSIERT SONST
          Ein blockierter Syscall TÖTET den Prozess mit SIGSYS (status=31/SYS)
          statt ihm einen Fehler zurückzugeben. Ergebnis: zehn Neustarts,
          dann start-limit-hit, Dienst dauerhaft tot.

        WARUM DAS SCHWER ZU FINDEN IST
          Der Filter wirkt großzügig. Auf q958 war das node-Profil sogar LOCKERER
          als das full-Profil (kein ~@resources) — und starb trotzdem, während
          Navidrome unter dem strengeren Profil lief. Die Fehlermeldung nennt
          weder den Syscall noch den Filter als Ursache.

        LÖSUNG
          SystemCallErrorNumber = "EPERM";
          Abgewiesene Syscalls liefern dann einen Fehler statt eines Todesurteils.
          Node behandelt EPERM als normalen Fehler. Die Härtung bleibt in Kraft.

        Belegt am 2026-07-20 auf q958. Siehe LEARNINGS.md, L4.
      '';
    }

    # ══════════════════════════════════════════════════════════════════════════
    # L2 / L5 — Zustandsverzeichnis nicht deklariert
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !cfg.jellyfin.enable
        || lib.any (r: lib.hasInfix "/var/lib/jellyfin " r) (config.systemd.tmpfiles.rules or [ ]);
      message = ''
        [mediNix] jellyfin ist aktiviert, aber /var/lib/jellyfin wird nirgends
        per systemd.tmpfiles.rules deklariert.

        WAS PASSIERT SONST
          Die Unit setzt ReadWritePaths=/var/lib/jellyfin. Diese Direktive
          verlangt ein EXISTIERENDES Verzeichnis. Fehlt es, scheitert schon das
          Einrichten des Mount-Namespace:
              "Failed to set up mount namespacing: /var/lib/jellyfin:
               No such file or directory"
          Der Dienst kommt gar nicht erst zum Start.

        WARUM DAS LANGE UNBEMERKT BLEIBT
          Solange irgendetwas das Verzeichnis zufällig anlegt, läuft alles. Erst
          nach einem rm -rf — oder auf einer FRISCHEN Installation bei jemand
          anderem — fällt es auf.

        PRÜFFRAGE FÜR JEDES MODUL
          Läuft der Dienst nach "rm -rf <sein Zustandsverzeichnis>" wieder an?
          Wenn nein, ist er nicht neuinstallationsfest.

        LÖSUNG
          Elternverzeichnis EXPLIZIT und VOR allen Unterordnern deklarieren:
            "d /var/lib/jellyfin 0700 jellyfin jellyfin -"
          Ein implizit über einen Unterordner angelegtes Elternverzeichnis
          gehört root:root — dann kann ein Dienst mit User= nicht schreiben.

        Belegt am 2026-07-20 auf q958. Siehe LEARNINGS.md, L2 und L5.
      '';
    }

    # ══════════════════════════════════════════════════════════════════════════
    # GPU: Hersteller passt nicht zum Gerät
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !(cfg.enable && cfg.jellyfin.enable)
        || cfg.hardware.accel != "nvidia"
        || cfg.hardware.renderDevice == null
        || !(lib.hasPrefix "/dev/dri" cfg.hardware.renderDevice);
      message = ''
        [mediNix] hardware.accel = "nvidia", aber renderDevice zeigt auf /dev/dri.

        WAS PASSIERT SONST
          NVIDIA nutzt NVENC/NVDEC über /dev/nvidia* — NICHT die DRI-Render-Nodes.
          ffmpeg findet dort kein passendes Gerät und fällt STILL auf
          CPU-Transkodierung zurück. Es gibt keine Fehlermeldung; man merkt es
          nur an der Prozessorlast.

        LÖSUNG
          Bei accel = "nvidia" renderDevice auf null lassen — ffmpeg wählt die
          Karte per Index. Der Wert ist nur für DRI-basierte Pfade (Intel/AMD)
          gedacht, etwa um bei mehreren GPUs renderD129 statt renderD128 zu
          nehmen.
      '';
    }
  ];
}
