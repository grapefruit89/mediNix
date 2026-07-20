{
  description = "mediNix -- eigenstaendiger NixOS-Medienstack";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let system = "x86_64-linux";
    in {
      # Das Modul selbst -- so binden Konsumenten es ein.
      nixosModules.default = ./.;
      nixosModules.mediNix = ./.;

      # Pruefkonfiguration: existiert, damit das Modul ueberhaupt
      # evaluierbar ist. Kein Auslieferungsziel.
      nixosConfigurations.check = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./checks/minimal-host.nix ./. ];
      };

      checks.${system}.eval =
        self.nixosConfigurations.check.config.system.build.toplevel;
    };
}
