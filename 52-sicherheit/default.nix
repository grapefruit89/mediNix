# 5N0 -- Block-ID / Fundament der Dekade (ADR-8000: N0 sammelt N1-N9, ist nie
# selbst ein Dienst). Importiert rekursiv jede 5NN-Datei/-Unterordner der Dekade.
{ lib, ... }:
{
  imports =
    let
      hier = builtins.readDir ./.;
      istDienst =
        name: typ:
        (typ == "regular" && builtins.match "^[0-9]{3}-.*\\.nix$" name != null)
        || (typ == "directory" && builtins.match "^[0-9]{3}-.*" name != null);
    in
    map (n: ./. + "/${n}") (lib.attrNames (lib.filterAttrs istDienst hier));
}
