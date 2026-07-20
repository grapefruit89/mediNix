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
    }:
    let
      base = {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce privateDevices;
        NoNewPrivileges = lib.mkForce true;
        ProtectKernelTunables = lib.mkForce true;
        ProtectKernelModules = lib.mkForce true;
        ProtectControlGroups = lib.mkForce true;
        RestrictRealtime = lib.mkForce (profile != "streamer");
        RestrictSUIDSGID = lib.mkForce true;
        LockPersonality = lib.mkForce true;
        RestrictAddressFamilies = lib.mkForce [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ReadWritePaths = readWritePaths;
      }
      // lib.optionalAttrs (profile == "full") {
        CapabilityBoundingSet = lib.mkForce "";
        DevicePolicy = lib.mkForce "closed";
        SystemCallFilter = lib.mkForce [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
      }
      // lib.optionalAttrs (profile == "dotnet") {
        SystemCallFilter = lib.mkForce [
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
        CapabilityBoundingSet = lib.mkForce "";
        SystemCallFilter = lib.mkForce [
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
        SystemCallErrorNumber = lib.mkForce "EPERM";

        # Fehlte im Vergleich zum full-Profil. Ohne native koennen Syscalls
        # ueber eine fremde ABI den Filter umgehen -- eine Luecke, kein Feature.
        SystemCallArchitectures = lib.mkForce "native";
      }
      // lib.optionalAttrs (profile == "streamer") {
        UMask = lib.mkForce "0002";
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
          Restart = lib.mkForce "always";
          RestartSec = lib.mkForce "5s";
          RuntimeDirectory = lib.mkForce "${name}-transcode";
          RuntimeDirectoryMode = lib.mkForce "0700";
          ReadOnlyPaths = readOnlyPaths;
        }
        gpuExtra
        extraSystemd
      ];
    };
}
