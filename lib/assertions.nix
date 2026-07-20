# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Verbotsschilder an den Türen, an denen wir uns die Finger geklemmt haben
#   docs:
#     - LEARNINGS.md
#   tags: [assertions, guards, lockout]
# ---
#
# WOZU DIESE DATEI
#
# Jede Prüfung hier steht für einen Fehler, der real passiert ist und Stunden
# gekostet hat. Sie existiert, damit derselbe Fehler nicht zweimal gemacht
# werden kann — weder von einem Menschen noch von einem Agenten.
#
# REGEL FÜR ERGÄNZUNGEN
#
# Eine neue Assertion kommt hier hinein, wenn drei Dinge zutreffen:
#   1. Der Fehler ist wirklich passiert (nicht ausgedacht)
#   2. Der naheliegende, erste Weg war der falsche
#   3. Die Fehlermeldung des Systems half nicht weiter
#
# Jede Assertion nennt in ihrer Meldung: was falsch ist, WARUM es schiefgeht,
# und was stattdessen zu tun ist. Eine Assertion, die nur "ungültig" sagt,
# ist eine verpasste Gelegenheit.
#
# ══════════════════════════════════════════════════════════════════════════
# GRENZE — was hier NIEMALS geprüft werden darf (ADR-5040)
# ══════════════════════════════════════════════════════════════════════════
#
# Assertions dürfen ausschließlich **mediNix-eigene Optionen** und die
# **von mediNix selbst erzeugten Units** prüfen.
#
# VERBOTEN sind Urteile über die Umgebung des Nutzers:
#
#   ✗ "Es läuft kein Authelia/Pocket-ID/oauth2-proxy"
#     Wer einen fertigen Auth-Stack betreibt, bekommt von uns keinen
#     zerschossenen Build. Wir wissen nicht, wie seine Anmeldung heißt,
#     wo sie läuft oder ob sie überhaupt eine systemd-Unit ist — sie könnte
#     auf einer anderen Maschine stehen.
#
#   ✗ "Die Firewall ist nicht aktiv" / "SSH erlaubt Passwörter"
#     Host-Zuständigkeit. Ein Medienstack, der die Zugangsverwaltung des
#     Nutzers bewertet, ist übergriffig.
#
#   ✗ "Der Kernel hat Einstellung X nicht"
#     Siehe ADR-5040: mediNix härtet seine Dienste, nicht die Maschine.
#
# ERLAUBT ist dagegen, auf **Widersprüche in unserer eigenen Konfiguration**
# hinzuweisen — etwa: forward-auth eingeschaltet, aber kein Endpunkt gesetzt.
# Das ist kein Urteil über den Nutzer, sondern über unsere Optionen.
#
# Faustregel: Prüfe nur, was du selbst erzeugt hast.
{ lib, config }:
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
[

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
]
