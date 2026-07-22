# 594 -- Leitplanken der Domaene 54-transfer (SABnzbd).
{ config, ... }:
let
  cfg = config.grapefruitMedia;
in
{
  assertions = [
    # ══════════════════════════════════════════════════════════════════════════
    # SABnzbd zieht ein unfreies Paket
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !cfg.sabnzbd.enable
        || (config.nixpkgs.config.allowUnfree or false)
        || (config.nixpkgs.config.allowUnfreePredicate or null) != null;
      message = ''
        [mediNix] sabnzbd ist aktiviert, aber es ist weder allowUnfree noch ein
        allowUnfreePredicate gesetzt.

        WAS PASSIERT SONST
          SABnzbd zieht über seine Abhängigkeiten "unrar" — ein unfreies Paket.
          Der Build bricht mit einer Meldung ab, die SABnzbd nicht erwähnt, und
          man sucht an der falschen Stelle.

        WARUM KEIN ANDERES ENTPACKPROGRAMM
          Usenet-Releases sind praktisch immer RAR. Die freien Entpacker
          scheitern an RAR5 oder brauchen selbst wieder den unfreien Codec.
          unrar ist unfrei, aber kostenlos und uneingeschränkt nutzbar — die
          Lizenz verbietet nur, damit einen konkurrierenden Kompressor zu bauen.

        LÖSUNG — gezielt, nicht global
          nixpkgs.config.allowUnfreePredicate =
            pkg: builtins.elem (lib.getName pkg) [ "unrar" ];
      '';
    }
  ];
}
