# ---
# id: "usenet-confinement"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "WireGuard-VPN-Sandbox fuer SABnzbd + Prowlarr -- Leak-Schutz"
# provides: [usenet-vpn-verify, usenet-vpn-carrier.path, sabnzbd/prowlarr NetworkNamespace]
# requires: [grapefruitMedia.vpn, grapefruitMedia.usenet-confinement]
# tags: [vpn, wireguard, usenet, sandboxing, leak-protection]
# docs:
#   - docs/adr/5031-usenet-confinement.md
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgGlobal = config.grapefruitMedia;
  cfg = cfgGlobal.vpn;
  rebuildGuard = import ../lib/rebuild-guard.nix { inherit lib; };

  stateDir = "/var/lib/usenet-vpn";
  stateFile = "${stateDir}/verify.json";

  verifyBin = pkgs.writeShellScriptBin "usenet-vpn-verify" ''
    set -euo pipefail

    LOCK_FILE=/run/lock/usenet-vpn-verify.lock
    ${pkgs.coreutils}/bin/mkdir -p /run/lock
    exec 9>"$LOCK_FILE"
    ${pkgs.util-linux}/bin/flock -w 120 9 || {
      echo "usenet-vpn-verify: lock timeout after 120s"
      exit 1
    }

    IFACE=${cfg.interface}
    CHECK_URL="https://api.ipify.org"
    STATE_FILE=${stateFile}
    CACHE_TTL=60
    ${pkgs.coreutils}/bin/mkdir -p ${stateDir}

    if [[ -r "$STATE_FILE" ]] && ${pkgs.jq}/bin/jq -e '.ok == true' "$STATE_FILE" >/dev/null 2>&1; then
      checked_at="$(${pkgs.jq}/bin/jq -r '.checked_at' "$STATE_FILE")"
      checked_epoch="$(${pkgs.coreutils}/bin/date -d "$checked_at" +%s 2>/dev/null || echo 0)"
      now_epoch="$(${pkgs.coreutils}/bin/date +%s)"
      age=$((now_epoch - checked_epoch))
      if (( age >= 0 && age < CACHE_TTL )); then
        echo "usenet-vpn-verify: OK (cached ''${age}s ago)"
        exit 0
      fi
    fi

    if ! ${pkgs.iproute2}/bin/ip link show "$IFACE" &>/dev/null; then
      echo "usenet-vpn-verify: $IFACE missing"
      exit 1
    fi
    operstate="$(${pkgs.iproute2}/bin/ip -json link show "$IFACE" | ${pkgs.jq}/bin/jq -r '.[0].operstate')"
    if [[ "$operstate" != "UP" && "$operstate" != "UNKNOWN" ]]; then
      echo "usenet-vpn-verify: $IFACE link down (operstate=$operstate)"
      exit 1
    fi
    if ! ${pkgs.iproute2}/bin/ip -4 addr show dev "$IFACE" | grep -q "inet "; then
      echo "usenet-vpn-verify: $IFACE has no IPv4 address"
      exit 1
    fi

    HOST_IP=""
    for attempt in 1 2 3; do
      if HOST_IP="$(${pkgs.curl}/bin/curl -fsS --max-time 10 "$CHECK_URL" 2>/dev/null | tr -d '[:space:]')"; then
        [[ -n "$HOST_IP" ]] && break
      fi
      sleep 2
    done
    if [[ -z "$HOST_IP" ]]; then
      echo "usenet-vpn-verify: no host egress after retries"
      exit 1
    fi

    USENET_IP=""
    for attempt in 1 2 3; do
      if USENET_IP="$(${pkgs.curl}/bin/curl -fsS --max-time 10 --interface "$IFACE" "$CHECK_URL" 2>/dev/null | tr -d '[:space:]')"; then
        [[ -n "$USENET_IP" ]] && break
      fi
      sleep 2
    done

    if [[ -z "$USENET_IP" ]]; then
      echo "usenet-vpn-verify: no egress via $IFACE after retries"
      exit 1
    fi

    if [[ "$HOST_IP" == "$USENET_IP" ]]; then
      echo "usenet-vpn-verify: LEAK host=$HOST_IP usenet=$USENET_IP"
      ${pkgs.jq}/bin/jq -n \
        --arg host "$HOST_IP" \
        --arg vpn "$USENET_IP" \
        --arg ts "$(${pkgs.coreutils}/bin/date -Iseconds)" \
        '{ok: false, host_ip: $host, vpn_ip: $vpn, checked_at: $ts, error: "leak"}' \
        > "$STATE_FILE"
      chmod 0644 "$STATE_FILE"
      ${pkgs.systemd}/bin/systemctl stop sabnzbd.service prowlarr.service 2>/dev/null || true
      exit 1
    fi

    ${pkgs.jq}/bin/jq -n \
      --arg host "$HOST_IP" \
      --arg vpn "$USENET_IP" \
      --arg ts "$(${pkgs.coreutils}/bin/date -Iseconds)" \
      '{ok: true, host_ip: $host, vpn_ip: $vpn, checked_at: $ts}' > "$STATE_FILE"
    chmod 0644 "$STATE_FILE"

    echo "usenet-vpn-verify: OK host=$HOST_IP vpn=$USENET_IP"
  '';

  statusBin = pkgs.writeShellScriptBin "usenet-vpn-status" ''
    set -euo pipefail
    STATE_FILE=${stateFile}
    IFACE=${cfg.interface}

    if ! ${pkgs.iproute2}/bin/ip link show "$IFACE" &>/dev/null; then
      echo "VPN interface missing"
      exit 1
    fi
    operstate="$(${pkgs.iproute2}/bin/ip -json link show "$IFACE" | ${pkgs.jq}/bin/jq -r '.[0].operstate')"
    if [[ "$operstate" != "UP" && "$operstate" != "UNKNOWN" ]]; then
      echo "VPN interface down"
      exit 1
    fi
    if [[ ! -r "$STATE_FILE" ]]; then
      echo "No verify state yet"
      exit 1
    fi
    if ! ${pkgs.jq}/bin/jq -e '.ok == true' "$STATE_FILE" >/dev/null; then
      echo "Last verify failed"
      exit 1
    fi
    echo "OK"
  '';

  sandboxAttrs = {
    bindsTo = [ "sys-subsystem-net-devices-${cfg.interface}.device" ];
    after = [ "sys-subsystem-net-devices-${cfg.interface}.device" ];
    serviceConfig = {
      RestrictNetworkInterfaces = [
        "lo"
        cfg.interface
      ];
      BindReadOnlyPaths = [ "/etc/usenet-resolv.conf:/etc/resolv.conf" ];
      PrivateIPC = true;
      RestrictNamespaces = true;
      ProcSubset = "pid";
      InaccessiblePaths = [ "/sys/class/net" ];
    };
  };
in
{
  config = lib.mkIf (cfgGlobal.enable && cfgGlobal.usenet-confinement.enable) {
    environment.systemPackages = [
      verifyBin
      statusBin
    ];

    environment.etc."usenet-resolv.conf".text = lib.concatMapStrings (
      dns: "nameserver ${dns}\n"
    ) cfg.dns;

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "f ${stateFile} 0644 root root - -"
    ];

    systemd.services.usenet-vpn-verify = {
      description = "Usenet VPN egress leak check (oneshot, event-triggered)";
      after = [
        "sys-subsystem-net-devices-${cfg.interface}.device"
        "network-online.target"
      ];
      wants = [ "sys-subsystem-net-devices-${cfg.interface}.device" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${verifyBin}/bin/usenet-vpn-verify";
        StartLimitIntervalSec = 0;
        StartLimitBurst = 0;
      };
    };

    systemd.paths.usenet-vpn-carrier = {
      unitConfig = rebuildGuard.pathUnitGuard;
      description = "Verify Usenet VPN egress when carrier changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/sys/class/net/${cfg.interface}";
        PathChanged = "/sys/class/net/${cfg.interface}/carrier";
        Unit = "usenet-vpn-verify.service";
        MakeDirectory = false;
      };
    };

    systemd.paths.usenet-vpn-operstate = {
      description = "Verify Usenet VPN egress when operstate changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/sys/class/net/${cfg.interface}/operstate";
        PathChanged = "/sys/class/net/${cfg.interface}/operstate";
        Unit = "usenet-vpn-verify.service";
        MakeDirectory = false;
      };
    };

    systemd.services.sabnzbd = lib.recursiveUpdate sandboxAttrs {
      serviceConfig.ExecStartPre = lib.mkOrder 10 [
        "+${verifyBin}/bin/usenet-vpn-verify"
      ];
    };
    systemd.services.prowlarr = lib.recursiveUpdate sandboxAttrs {
      serviceConfig.ExecStartPre = lib.mkOrder 10 [
        "+${verifyBin}/bin/usenet-vpn-verify"
      ];
    };
  };
}
