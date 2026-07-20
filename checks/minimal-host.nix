# Minimalster Host, damit das Modul evaluiert werden kann.
# Bewusst nicht bootfaehig -- der Zweck ist die Auswertung, nicht der Betrieb.
{ ... }:
{
  boot.loader.grub.enable = false;
  fileSystems."/" = { device = "/dev/disk/by-label/dummy"; fsType = "ext4"; };
  system.stateVersion = "26.05";

  grapefruitMedia.enable = true;
}
