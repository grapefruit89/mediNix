{ ... }:
{
  sentinel = "/run/nixos/rebuild-in-progress";
  pathUnitGuard = {
    ConditionPathExists = "!/run/nixos/rebuild-in-progress";
  };
}
