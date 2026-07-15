# ---
# meta:
#   id: NIXH-05-LIB-002
#   layer: 5
#   role: lib
#   purpose: mkService / mkStreamer — systemd-Hardening, persistDirs, optional Caddy
#   tags:
#     - factory
#     - caddy
#     - systemd
# ---
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
      socketPath ? null,
      host ? null,
      mode ? "sso",
      upstreamHost ? "127.0.0.1",
      readWritePaths ? [ ],
      readOnlyPaths ? [ ],
      privateDevices ? true,
      hardeningProfile ? "full",
      memoryPolicy ? null,
      extraSystemd ? { },
      extraCaddy ? "",
      caddyOnly ? false,
      persist ? true,
      persistDirs ? [ ],
      cacheDir ? "/var/cache/${name}",
      manageIngress ? null,
      ipAllow ? null,
    }:
    let
      domain = if config ? grapefruitMedia then config.grapefruitMedia.domain else "grapefruit-media.local";
      vhost = if host != null then host else "${name}.${domain}";
      doIngress = if manageIngress != null then manageIngress else false;
      paths = lib.unique (defaultPersistDirs name persistDirs cacheDir);
    in
    lib.mkMerge [
      (lib.mkIf (!caddyOnly) {
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
          ++ lib.optional (ipAllow != null) {
            IPAddressAllow = lib.mkDefault ipAllow;
            IPAddressDeny = lib.mkDefault "any";
          }
          ++ [ extraSystemd ]
        );
      })
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
      manageIngress ? false,
      mode ? "sso",
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
        mode
        memoryPolicy
        persistDirs
        manageIngress
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
