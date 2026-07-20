# ---
# id: "rebuild-guard"
# domain: "50"
# status: "active"
# layer: 5
# role: lib
# purpose: "systemd-Path-Unit Guard: verhindert Trigger wehrend nixos-rebuild"
# tags: [lib, systemd, path, guard]
# ---
_: {
  sentinel = "/run/nixos/rebuild-in-progress";
  pathUnitGuard = {
    ConditionPathExists = "!/run/nixos/rebuild-in-progress";
  };
}
