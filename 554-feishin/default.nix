# ---
# id: "feishin"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Feishin — alternative Weboberflaeche fuer Navidrome/Jellyfin/OpenSubsonic"
# provides: [feishin.local vHost]
# requires: [ein laufender Musikserver — Navidrome, Jellyfin oder OpenSubsonic]
# tags: [music, web, static, navidrome]
# ---
#
# BESONDERHEIT: Dieser Dienst hat KEINEN Prozess.
#
# feishin-web sind reine statische Dateien (index.html + assets). Caddy
# liefert sie direkt aus -- keine systemd-Unit, kein Port, kein Benutzer,
# nichts zu haerten. Der Eintrag in der Registry traegt deshalb static = true.
#
# ABGRENZUNG, weil der Name in die Irre fuehrt:
# Das Projekt nennt sich "self-hosted music player". Selbst hosten kann man es,
# ein Musikserver ist es NICHT -- es liest keine Dateien und verwaltet keine
# Bibliothek. Laut Projekt-FAQ spricht es die API von Navidrome, Jellyfin oder
# einem OpenSubsonic-Server. Ohne einen davon zeigt es nur eine Anmeldemaske.
#
# Es ERSETZT Navidrome also nicht, sondern setzt eine zweite Oberflaeche davor.
{
  config,
  lib,
  ...
}:
let
  cfg = config.grapefruitMedia;
in
{
  options.grapefruitMedia.feishin = {
    enable = lib.mkEnableOption "Feishin — alternative Weboberflaeche fuer den Musikserver";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      defaultText = lib.literalExpression "pkgs.feishin-web";
      description = ''
        Paket mit den statischen Dateien. null = pkgs.feishin-web.

        Wichtig: feishin-web, nicht feishin. Letzteres ist die Electron-
        Desktop-Anwendung und enthaelt keine ausliefer­baren Web-Dateien.
      '';
    };

    serverUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://navidrome.local";
      description = ''
        Adresse des Musikservers, zu dem sich Feishin verbindet.

        null = der Nutzer traegt sie beim ersten Start selbst ein.
        Gesetzt = vorbelegt, spart einen Handgriff.

        Der Wert ist die Adresse, die der BROWSER erreichen muss, nicht der
        Server. Also http://navidrome.local, nicht 127.0.0.1:5430 -- letzteres
        waere aus Sicht des Browsers dessen eigener Rechner.
      '';
    };

    serverType = lib.mkOption {
      type = lib.types.enum [
        "navidrome"
        "jellyfin"
        "subsonic"
      ];
      default = "navidrome";
      description = "Art des Musikservers. Nur relevant, wenn serverUrl gesetzt ist.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.feishin.enable) {
    assertions = [
      {
        assertion = cfg.navidrome.enable || cfg.jellyfin.enable || cfg.feishin.serverUrl != null;
        message = ''
          [mediNix] feishin ist aktiviert, aber es laeuft weder navidrome noch
          jellyfin, und feishin.serverUrl ist nicht gesetzt.

          Feishin ist eine Oberflaeche, kein Musikserver -- es braucht zwingend
          einen Server, dessen API es sprechen kann. Ohne einen davon zeigt es
          nur eine Anmeldemaske, die nirgendwohin fuehrt.

          LOESUNG, eine davon:
            grapefruitMedia.navidrome.enable = true;
            grapefruitMedia.jellyfin.enable = true;
            grapefruitMedia.feishin.serverUrl = "http://mein-server:4533";
        '';
      }
    ];
  };
}
