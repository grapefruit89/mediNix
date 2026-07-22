# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: systemd socket-proxyd on-demand HTTP — public socket, internal backend (+offset)
#   docs:
#     - 50-core/adr/5033-systemd-socket-on-demand.md
#   tags:
#     - on-demand
#     - systemd
#     - socket-activation
# ---
{
  lib,
  pkgs,
  internalOffset,
  idleTimeoutSec ? 1800,
}:
let
  bindAddr = "127.0.0.1";
  proxyBin = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  ss = "${pkgs.iproute2}/bin/ss";
  grep = "${pkgs.gnugrep}/bin/grep";
  date = "${pkgs.coreutils}/bin/date";
  sleep = "${pkgs.coreutils}/bin/sleep";
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  rm = "${pkgs.coreutils}/bin/rm";
  cat = "${pkgs.coreutils}/bin/cat";

  internalPort = publicPort: publicPort + internalOffset;

  startBackendAndWait =
    {
      backend,
      port,
    }:
    pkgs.writeShellScript "start-${backend}" ''
      ${systemctl} start ${backend}.service
      i=0
      while [ "$i" -lt 300 ]; do
        if ${pkgs.curl}/bin/curl -fsS --max-time 1 "http://${bindAddr}:${toString port}/" >/dev/null 2>&1 \
          || ${ss} -H -tln "sport = :${toString port}" | ${grep} -q .; then
          exit 0
        fi
        i=$((i + 1))
        ${sleep} 0.2
      done
      echo "timeout waiting for backend ${backend} on :${toString port}" >&2
      exit 1
    '';
in
{
  inherit bindAddr internalOffset internalPort;

  mkProxy =
    {
      name,
      publicPort,
    }:
    let
      backend = "${name}-backend";
      iPort = internalPort publicPort;
    in
    {
      systemd.sockets.${name} = {
        description = "On-demand public socket for ${name} (:${toString publicPort})";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "${bindAddr}:${toString publicPort}";
          Accept = "no";
        };
      };

      systemd.services.${name} = {
        description = lib.mkForce "On-demand HTTP proxy for ${name} → :${toString iPort}";
        requires = lib.mkForce [ "${name}.socket" ];
        after = lib.mkForce [ "${name}.socket" ];
        partOf = lib.mkForce [ "${name}.socket" ];
        wantedBy = lib.mkForce [ ];
        environment = lib.mkForce { };
        unitConfig = {
          StartLimitIntervalSec = lib.mkForce 0;
          StartLimitBurst = lib.mkForce 0;
        };
        serviceConfig = {
          PermissionsStartOnly = lib.mkForce true;
          Type = lib.mkForce "simple";
          ExecStartPre = lib.mkForce [
            "${startBackendAndWait {
              inherit backend;
              port = iPort;
            }}"
          ];
          ExecStart = lib.mkForce "${proxyBin} ${bindAddr}:${toString iPort}";
          BindReadOnlyPaths = lib.mkForce [ ];
          CapabilityBoundingSet = lib.mkForce [ "CAP_NET_BIND_SERVICE" ];
          DeviceAllow = lib.mkForce [ ];
          DynamicUser = lib.mkForce false;
          EnvironmentFile = lib.mkForce [ ];
          LockPersonality = lib.mkForce false;
          MemoryDenyWriteExecute = lib.mkForce false;
          OOMScoreAdjust = lib.mkForce "0";
          PrivateDevices = lib.mkForce false;
          PrivateUsers = lib.mkForce false;
          ProtectClock = lib.mkForce false;
          ProtectControlGroups = lib.mkForce false;
          ProtectHostname = lib.mkForce false;
          ProtectKernelLogs = lib.mkForce false;
          ProtectKernelModules = lib.mkForce false;
          ProtectKernelTunables = lib.mkForce false;
          RestrictNamespaces = lib.mkForce false;
          RestrictRealtime = lib.mkForce false;
          RestrictSUIDSGID = lib.mkForce false;
          RootDirectory = lib.mkForce "";
          RuntimeDirectory = lib.mkForce "";
          StateDirectory = lib.mkForce "";
          SystemCallArchitectures = lib.mkForce "";
          SystemCallErrorNumber = lib.mkForce "";
          SystemCallFilter = lib.mkForce "";
          WorkingDirectory = lib.mkForce "";
          User = lib.mkForce "";
          Group = lib.mkForce "";
          Restart = lib.mkForce "no";
          NoNewPrivileges = lib.mkForce false;
          PrivateTmp = lib.mkForce false;
          ProtectSystem = lib.mkForce false;
          ProtectHome = lib.mkForce false;
          RestrictAddressFamilies = lib.mkForce [ ];
        };
      };
    };

  mkIdleStop =
    {
      name,
      publicPort,
    }:
    let
      backend = "${name}-backend";
      iPort = internalPort publicPort;
      stampDir = "/run/${name}-idle";
      idleStopScript = pkgs.writeShellScript "${name}-idle-stop" ''
        set -euo pipefail
        BACKEND="${backend}.service"
        PROXY="${name}.service"
        STAMP="${stampDir}/last_activity"

        if ! ${systemctl} is-active --quiet "$BACKEND"; then
          exit 0
        fi

        ${mkdir} -p "${stampDir}"

        if ${ss} -H -tn state established "( sport = :${toString iPort} or sport = :${toString publicPort} )" | ${grep} -q .; then
          ${date} +%s > "$STAMP"
          exit 0
        fi

        NOW=$(${date} +%s)
        if [ -f "$STAMP" ]; then
          LAST=$(${cat} "$STAMP")
        else
          ENTER=$(${systemctl} show "$BACKEND" -p ActiveEnterTimestamp --value)
          LAST=$(${date} -d "$ENTER" +%s 2>/dev/null || echo "$NOW")
        fi

        if [ "$((NOW - LAST))" -lt ${toString idleTimeoutSec} ]; then
          exit 0
        fi

        ${systemctl} stop "$PROXY" "$BACKEND" || true
        ${rm} -f "$STAMP"
      '';
    in
    {
      systemd.services."${name}-idle-stop" = {
        description = "Stop ${name} backend after ${toString idleTimeoutSec}s without connections";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = idleStopScript;
        };
      };

      systemd.timers."${name}-idle-stop" = {
        description = "Check ${name} backend idle every 5 minutes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = "5min";
          AccuracySec = "1min";
        };
      };
    };
}
