# 591 -- Leitplanken der Domaene 51-zugang (Ingress, mDNS, Auth, Domain).
# Assertions aus ADR-8000 + 50-core/LEARNINGS.md; jede belegt einen realen Fehler.
{ config, lib, ... }:
let
  cfg = config.grapefruitMedia;
  # Dienste mit Weboberfläche — die Menge, die Ingress und mDNS betreffen
  uiServices = lib.filter (n: n != "") [
    (lib.optionalString cfg.jellyfin.enable "jellyfin")
    (lib.optionalString cfg.jellyseerr.enable "jellyseerr")
    (lib.optionalString cfg.sonarr.enable "sonarr")
    (lib.optionalString cfg.radarr.enable "radarr")
    (lib.optionalString cfg.readarr.enable "readarr")
    (lib.optionalString cfg.lidarr.enable "lidarr")
    (lib.optionalString cfg.prowlarr.enable "prowlarr")
    (lib.optionalString cfg.sabnzbd.enable "sabnzbd")
    (lib.optionalString cfg.audiobookshelf.enable "audiobookshelf")
    (lib.optionalString cfg.navidrome.enable "navidrome")
  ];

  anyEnabled = uiServices != [ ];
in
{
  assertions = [
    # ══════════════════════════════════════════════════════════════════════════
    # L1 — mDNS publiziert nichts, meldet aber Erfolg
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !(cfg.enable && cfg.discovery.mdns.enable && anyEnabled)
        || (config.services.avahi.publish.userServices or false);
      message = ''
        [mediNix] mDNS ist aktiviert, aber services.avahi.publish.userServices = false.

        WAS PASSIERT SONST
          Es wird KEIN einziger {service}.local-Name veröffentlicht. avahi-publish
          wird von avahi-daemon abgewiesen mit:
              "Failed to create entry group: Not permitted"
          Der Dienst endet nach ~50 ms — mit Status 0/SUCCESS. Er meldet also
          Erfolg, während nichts erreichbar ist, und Restart=on-failure greift nie.

        WARUM DER ERSTE WEG NICHT REICHT
          publish.enable = true und publish.addresses = true wirken plausibel und
          genügen NICHT. Sie erlauben dem Daemon, EIGENE Adressen zu publizieren.
          userServices erlaubt es CLIENTS, eigene Einträge beizusteuern — und
          avahi-publish ist genau so ein Client. Zwei verschiedene Dinge mit
          ähnlich klingenden Namen. Auch als root reproduzierbar; es ist keine
          Sandbox-Frage, sondern eine Daemon-Richtlinie
          (nixpkgs avahi-daemon.nix: disable-user-service-publishing).

        LÖSUNG
          services.avahi.publish.userServices = true;

        Belegt am 2026-07-20 auf q958. Siehe LEARNINGS.md, L1.
      '';
    }

    # ══════════════════════════════════════════════════════════════════════════
    # Aussperrung: .local hinter Anmeldung
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !(cfg.enable && cfg.ingress.enable && cfg.ingress.auth.mode == "forward-auth")
        || cfg.ingress.auth.localBypass;
      message = ''
        [mediNix] forward-auth ist aktiv, aber ingress.auth.localBypass = false.

        WAS PASSIERT SONST
          Auch die .local-Namen landen hinter der Anmeldung. Geräte ohne
          brauchbare Tastatur und ohne Passkey-Unterstützung — Fire TV, Chromecast,
          Smart-TV, Sonos — kommen dann NICHT MEHR an ihre Dienste. Genau die
          Geräte, für die .local gedacht ist.

        WARUM DAS KEIN SICHERHEITSLOCH IST
          .local ist reiner Multicast im LAN (RFC 6762, TTL 1). Es verlässt das
          physische Netz nie, taucht in keinem öffentlichen DNS auf und läuft
          auch nicht durch einen WireGuard-Tunnel. Wer im LAN steht, ist bereits
          drin. Die Domain-Variante bleibt authentifiziert.

        LÖSUNG
          ingress.auth.localBypass = true;   (der Default)
          Nur bewusst abschalten, wenn wirklich JEDER Zugriff eine Anmeldung
          braucht — und dann wissen, dass der Fernseher draußen bleibt.

        HINWEIS ZUR ABGRENZUNG
          Diese Prüfung betrifft AUSSCHLIESSLICH mediNix-eigene Optionen. Sie
          sagt nichts darüber, welcher Auth-Anbieter läuft und ob er läuft —
          Pocket-ID, oauth2-proxy, Authelia oder etwas ganz anderes ist deine
          Entscheidung und womöglich gar nicht auf dieser Maschine.
      '';
    }

    # ══════════════════════════════════════════════════════════════════════════
    # forward-auth ohne Endpunkt — Widerspruch in UNSERER Konfiguration
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !(cfg.enable && cfg.ingress.enable && cfg.ingress.auth.mode == "forward-auth")
        || (cfg.ingress.auth.upstream or "") != "";
      message = ''
        [mediNix] ingress.auth.mode = "forward-auth", aber kein Upstream gesetzt.

        WAS PASSIERT SONST
          Caddy erzeugt eine forward_auth-Direktive ohne Ziel. Jede
          authentifizierte Anfrage läuft in einen Fehler — die Domain-Namen sind
          dann unbrauchbar, während .local (bei localBypass) weiter funktioniert.
          Das Fehlerbild ist verwirrend: "manche Adressen gehen, andere nicht".

        LÖSUNG
          ingress.auth.upstream = "127.0.0.1:4180";   # oder wo dein Proxy lauscht

        ABGRENZUNG
          Wir prüfen NUR, dass DU uns ein Ziel genannt hast — nicht, ob dort
          etwas lauscht, und schon gar nicht, welche Software das ist. Ein
          bestehender Authelia- oder Pocket-ID-Stack wird von mediNix weder
          erkannt noch bewertet noch angefasst.
      '';
    }

    # ══════════════════════════════════════════════════════════════════════════
    # Ingress: Reservierung statt nur Obergrenze
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion =
        !(cfg.enable && cfg.ingress.enable && cfg.ingress.mode == "standalone")
        || (
          (config.systemd.services.caddy-media.serviceConfig.MemoryMax or null) == null
          || (config.systemd.services.caddy-media.serviceConfig.MemoryMin or null) != null
        );
      message = ''
        [mediNix] caddy-media hat MemoryMax, aber kein MemoryMin.

        WAS PASSIERT SONST
          MemoryMax ist eine OBERGRENZE — das Gegenteil einer Zusicherung. Unter
          Speicherdruck kann der Kernel dem Ingress alles wegnehmen. Hängt Caddy,
          hängt JEDER Dienst dahinter, auch die mit reichlich Speicher.

        WARUM OOMScoreAdjust ALLEIN NICHT GENÜGT
          OOMScoreAdjust wirkt auf den Kernel-OOM-Killer. systemd-oomd ist ein
          ZWEITER, unabhängiger Mechanismus, der nach Druck (PSI) entscheidet und
          OOMScoreAdjust IGNORIERT. Auf q958 gemessen: oomd war aktiv,
          ManagedOOMPreference stand auf "none" — der Ingress war trotz -500
          jederzeit abschussfähig.

        LÖSUNG
          MemoryMin = "64M";                    harte Reservierung
          MemoryLow = "128M";                   weiche Reservierung
          ManagedOOMPreference = "avoid";       gegen systemd-oomd
      '';
    }

    # ══════════════════════════════════════════════════════════════════════════
    # .local darf nie eine echte Domain sein
    # ══════════════════════════════════════════════════════════════════════════
    {
      assertion = cfg.domain == null || !(lib.hasSuffix ".local" cfg.domain);
      message = ''
        [mediNix] grapefruitMedia.domain endet auf ".local" — das ist reserviert.

        WAS PASSIERT SONST
          .local gehört ausschließlich mDNS (RFC 6762). Als Unicast-Domain
          verwendet, kollidiert es mit der Namensauflösung im LAN, und
          Let's Encrypt stellt dafür niemals ein Zertifikat aus. Der ACME-Pfad
          läuft dann endlos in Fehlversuche.

        LÖSUNG
          Eine echte Domain verwenden (media.example.com). Die .local-Namen
          entstehen ohnehin automatisch — dafür braucht es keine domain-Option.
      '';
    }
  ];
}
