# ---
# meta:
#   id: NIXH-05-LIB-002
#   layer: 5
#   role: lib
#   purpose: mkService / mkStreamer -- systemd-Hardening, persistDirs
#   tags: [factory, systemd, hardening]
#   docs:
#     - docs/adr/5030-media-stack-factory-hardening.md
# ---
# M2-Cleanup (Phase 4, 2026-07-15): entfernte tote Parameter:
#   mode, upstreamHost, socketPath, host, extraCaddy, caddyOnly,
#   manageIngress, ipAllow -- alle ohne Leser/Aufrufer.
{ lib }:
let
  systemdHardening =
    {
      readWritePaths ? [ ],
      privateDevices ? true,
      profile ? "full", # full | dotnet | node | streamer
      extra ? { },
      # Chamaeleon-Prinzip (ADR-5040): standardmaessig setzt das Modul nur
      # DEFAULTS. Wer im Rest seines Systems etwas anderes bestimmt hat --
      # GPU durchreichen, NAS einbinden, eigenes Profil -- gewinnt.
      #
      # Nix-Prioritaeten: mkForce = 50, normale Zuweisung = 100,
      # mkDefault = 1000. Niedriger gewinnt. Mit mkDefault schlaegt also jede
      # gewoehnliche Zuweisung des Nutzers unsere Vorgabe -- ohne dass er
      # mkForce schreiben muss.
      #
      # enforce = true kehrt das um (mkForce): fuer Betreiber, die die
      # Haertung gegen versehentliches Aufweichen schuetzen wollen.
      enforce ? false,
    }:
    let
      # harden = die Prioritaetsfunktion. Eine Stelle, nicht 26.
      harden = if enforce then lib.mkForce else lib.mkDefault;
      base = {
        ProtectSystem = harden "strict";
        ProtectHome = harden true;
        PrivateTmp = harden true;
        PrivateDevices = harden privateDevices;
        NoNewPrivileges = harden true;
        ProtectKernelTunables = harden true;
        ProtectKernelModules = harden true;
        ProtectControlGroups = harden true;
        RestrictRealtime = harden (profile != "streamer");
        RestrictSUIDSGID = harden true;
        LockPersonality = harden true;
        RestrictAddressFamilies = harden [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ReadWritePaths = readWritePaths;
      }
      // lib.optionalAttrs (profile == "full") {
        CapabilityBoundingSet = harden "";
        DevicePolicy = harden "closed";
        SystemCallFilter = harden [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
      }
      // lib.optionalAttrs (profile == "dotnet") {
        SystemCallFilter = harden [
          "@system-service"
          "~@privileged"
        ];
      }
      // lib.optionalAttrs (profile == "node") {
        # Node/libuv braucht Teile von @resources (sched_setaffinity, setrlimit),
        # deshalb wie dotnet nur ~@privileged statt der vollen full-Variante.
        # Bewusst KEIN DevicePolicy = "closed": Audiobookshelf kann QuickSync
        # nutzen und braucht dann Zugriff auf den Render-Node -- der Zugriff wird
        # ueber den privateDevices-Parameter gesteuert, nicht hier.
        CapabilityBoundingSet = harden "";
        SystemCallFilter = harden [
          "@system-service"
          "~@privileged"
        ];

        # 2026-07-20, q958: Audiobookshelf (Node 22) starb reproduzierbar mit
        # SIGSYS / status=31/SYS, 10 Neustarts, dann start-limit-hit.
        # Gegentest mit leerem SystemCallFilter: startet sofort und lauscht.
        # Damit ist der Filter als Ursache BEWIESEN -- welcher Syscall genau
        # blockiert wurde, ist NICHT ermittelt (dafuer braucht es die
        # Syscall-Nummer aus dem Audit-Log).
        #
        # Deshalb bewusst kein Erweitern der Allowlist auf Verdacht, sondern:
        # abgewiesene Syscalls liefern EPERM statt den Prozess zu toeten.
        # Node behandelt EPERM als normalen Fehler. Die Haertung bleibt in
        # Kraft -- nur die Reaktion ist nicht mehr toedlich.
        #
        # Sobald die Syscall-Nummer bekannt ist, gehoert sie hier explizit in
        # die Allowlist und diese Zeile kann wieder weg.
        SystemCallErrorNumber = harden "EPERM";

        # Fehlte im Vergleich zum full-Profil. Ohne native koennen Syscalls
        # ueber eine fremde ABI den Filter umgehen -- eine Luecke, kein Feature.
        SystemCallArchitectures = harden "native";
      }
      // lib.optionalAttrs (profile == "streamer") {
        UMask = harden "0002";
      };
    in
    lib.mkMerge [
      base
      extra
    ];

  defaultPersistDirs =
    name: persistDirs: cacheDir:
    if persistDirs != [ ] then
      persistDirs
    else
      lib.filter (p: p != null) [
        "/var/lib/${name}"
        cacheDir
      ];
in
rec {
  inherit systemdHardening;

  mkService =
    {
      config,
      name,
      port ? null,
      readWritePaths ? [ ],
      readOnlyPaths ? [ ],
      privateDevices ? true,
      hardeningProfile ? "full",
      memoryPolicy ? null,
      extraSystemd ? { },
      persist ? true,
      persistDirs ? [ ],
      cacheDir ? "/var/cache/${name}",
    }:
    let
      paths = lib.unique (defaultPersistDirs name persistDirs cacheDir);
    in
    lib.mkMerge [
      {
        systemd.services.${name}.serviceConfig = lib.mkMerge (
          [
            (systemdHardening {
              inherit readWritePaths privateDevices;
              profile = hardeningProfile;
            })
          ]
          ++ lib.optional (readOnlyPaths != [ ]) {
            ReadOnlyPaths = readOnlyPaths;
          }
          ++ lib.optional (memoryPolicy != null) memoryPolicy
          ++ [ extraSystemd ]
        );
      }
      (lib.mkIf (config.grapefruitMedia.persist.enable && persist && paths != [ ]) {
        grapefruitMedia.persist.extraPaths = paths;
      })
    ];

  mkStreamer =
    {
      config,
      name,
      port,
      readWritePaths ? [ ],
      readOnlyPaths ? [ ],
      useGPU ? false,
      memoryPolicy ? null,
      extraSystemd ? { },
      persistDirs ? [
        "/var/lib/${name}"
        "/var/cache/${name}"
      ],
    }:
    let
      gpuExtra =
        if useGPU then
          {
            # Bewusst mkForce, nicht harden: die GPU-Durchreichung MUSS die
            # Basisvorgabe PrivateDevices=true schlagen, sonst kann Jellyfin
            # nicht auf /dev/dri zugreifen und Transkodierung faellt auf CPU
            # zurueck. Wer useGPU=true setzt, hat sich bereits entschieden.
            # (Ausserdem liegt dieser Block in einem anderen let-Scope, in dem
            # die harden-Funktion nicht sichtbar ist.)
            PrivateDevices = lib.mkForce false;
            DeviceAllow = [
              "/dev/dri rw"
              "/dev/dri/card0 rw"
              "/dev/dri/renderD128 rw"
            ];
          }
        else
          { };
    in
    mkService {
      inherit
        config
        name
        port
        memoryPolicy
        persistDirs
        ;
      hardeningProfile = "streamer";
      privateDevices = !useGPU;
      inherit readWritePaths;
      extraSystemd = lib.mkMerge [
        {
          Restart = lib.mkDefault "always";
          RestartSec = lib.mkDefault "5s";
          RuntimeDirectory = lib.mkDefault "${name}-transcode";
          RuntimeDirectoryMode = lib.mkDefault "0700";
          ReadOnlyPaths = readOnlyPaths;
        }
        gpuExtra
        extraSystemd
      ];
    };
}
