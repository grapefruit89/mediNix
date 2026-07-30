# 593 -- Leitplanken der Domaene 53-beschaffung (.NET-*arr).
# Verhindert die .NET-JIT-Falle: MemoryDenyWriteExecute bricht die *arr reproduzierbar.
{ config, ... }:
let
  cfg = config.grapefruitMedia;
  dotnetArrs = [
    "prowlarr"
    "sonarr"
    "radarr"
    "lidarr"
    "readarr"
  ];
in
{
  assertions = map (svc: {
    assertion =
      !(cfg.${svc}.enable or false)
      || (config.systemd.services.${svc}.serviceConfig.MemoryDenyWriteExecute or false) != true;
    message = ''
      [mediNix] ${svc} (.NET) hat MemoryDenyWriteExecute = true.

      .NET braucht W+X-Speicher fuer den JIT -- MDWE bricht den Start reproduzierbar.
      Fuer die *arr MUSS MemoryDenyWriteExecute AUS bleiben. Die sichere Haertung
      laeuft ueber das 'dotnet'-Profil in lib/service-factory.nix (moderater
      SystemCallFilter ohne ~@resources, kein MDWE).
    '';
  }) dotnetArrs;
}
