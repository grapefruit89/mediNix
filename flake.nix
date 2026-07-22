# Eigenstaendiger Flake fuer mediNix.
#
# Bewusst OHNE zusaetzliche Flake-Inputs (kein treefmt-nix, kein flake-utils):
# jeder Input ist etwas, das brechen, veralten oder Sicherheitsfragen aufwerfen
# kann. Fuer drei Linter lohnt das nicht -- pkgs.runCommand genuegt.
{
  description = "mediNix -- eigenstaendiger NixOS-Medienstack";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      # Ein Check laeuft im Repo und erzeugt bei Erfolg eine leere Ausgabe.
      mkCheck =
        name: deps: script:
        pkgs.runCommand "check-${name}" { nativeBuildInputs = deps; } ''
          cd ${self}
          ${script}
          touch $out
        '';
    in
    {
      # ── Das Modul ────────────────────────────────────────────────────────
      nixosModules.default = ./.;
      nixosModules.mediNix = ./.;

      # ── Pruefkonfiguration ───────────────────────────────────────────────
      # Existiert, damit das Modul allein evaluierbar ist. Kein Auslieferungsziel.
      nixosConfigurations.check = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./checks/minimal-host.nix
          ./.
        ];
      };

      # Voller Stack -- baut jeden Dienst, anders als die minimale check-Config.
      nixosConfigurations.check-full = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./checks/full-host.nix
          ./.
        ];
      };

      # ── Formatter ────────────────────────────────────────────────────────
      # nixfmt ist der offizielle Nix-Formatter (RFC 166) und das, was die
      # nixpkgs-CI selbst benutzt (ci/treefmt.nix).
      #
      # NICHT nixfmt-rfc-style verwenden: seit 2025-07-14 nur noch ein Alias auf
      # nixfmt ("is now the same as pkgs.nixfmt which should be used instead",
      # pkgs/top-level/aliases.nix). Store-Pfade sind bitgleich.
      # nixfmt-classic ist entfernt, nixpkgs-fmt ist Community und nicht in der CI.
      # Bewusst nicht alejandra oder nixpkgs-fmt: wer sich an den Standard
      # haelt, muss Fremden nichts erklaeren.
      formatter.${system} = pkgs.nixfmt;

      # ── Checks ───────────────────────────────────────────────────────────
      checks.${system} = {

        # 1. Baut das Modul ueberhaupt?
        eval = self.nixosConfigurations.check.config.system.build.toplevel;

        # 1b. Baut der VOLLE Stack? (jeder Dienst, wie q958)
        #     minimal-host laesst Dienste aus -> eval baut fast nichts.
        #     Dieser Check faengt ein kaputtes Dienstmodul, bevor der Switch es tut.
        full = self.nixosConfigurations.check-full.config.system.build.toplevel;

        # 2. Ist alles formatiert? --check aendert nichts, es meldet nur.
        format = mkCheck "format" [ pkgs.nixfmt ] ''
          nixfmt --check $(find . -name '*.nix' -not -path './.git/*') \
            || { echo ""; echo "Nicht formatiert. Beheben mit:  nix fmt"; exit 1; }
        '';

        # 3. Anti-Patterns: baut zwar, ist aber schwer lesbar.
        statix = mkCheck "statix" [ pkgs.statix ] ''
          statix check . \
            || { echo ""; echo "Beheben mit:  statix fix ."; exit 1; }
        '';

        # 4. Toter Code.
        #    Genau das haette am 2026-07-20 Zeit gespart: ein toter Import
        #    (1091-ddclient.nix) blockierte den ersten Build auf echter
        #    Hardware und fiel erst dort auf. deadnix meldet so etwas sofort.
        deadnix = mkCheck "deadnix" [ pkgs.deadnix ] ''
          deadnix --fail . \
            || { echo ""; echo "Beheben mit:  deadnix --edit ."; exit 1; }
        '';

        # ═══════════════════════════════════════════════════════════════
        # 5. DIE RATSCHE -- Dezimalrahmen-Invarianten (ADR-8000).
        # ═══════════════════════════════════════════════════════════════
        # Faengt jede falsche Nummer beim `nix flake check`, BEVOR sie
        # ausgerollt wird: fuehrende 5, N00 nie ein Dienst, UID/Port-Formeln,
        # keine Doppel, mediaGid = 5000.
        dezimalrahmen =
          let
            reg = import ./lib/registry.nix { inherit lib; };
            svcNums = lib.mapAttrs (_: sv: sv.number) reg.services;
            nums = lib.attrValues svcNums;
            verstoesse = lib.filter (v: v != null) (
              lib.mapAttrsToList (
                name: num:
                let
                  projekt = num / 100;
                  rest = num - projekt * 100;
                  probleme = lib.concatStringsSep ", " (
                    lib.optional (projekt != 5) "fuehrende Ziffer ${toString projekt} != 5"
                    ++ lib.optional (rest == 0) "N00 darf kein Dienst sein"
                    ++ lib.optional (
                      reg.uids.${name} != num * 10
                    ) "UID ${toString reg.uids.${name}} != ${toString (num * 10)}"
                    ++ lib.optional (
                      reg.ports.${name} != num * 10
                    ) "Port ${toString reg.ports.${name}} != ${toString (num * 10)}"
                  );
                in
                if probleme == "" then null else "${name} (${toString num}): ${probleme}"
              ) svcNums
            );
            fehler =
              verstoesse
              ++ lib.optional (lib.length nums != lib.length (lib.unique nums)) "doppelte Nummern in der Registry"
              ++ lib.optional (reg.mediaGid != 5000) "mediaGid ${toString reg.mediaGid} != 5000";
          in
          if fehler == [ ] then
            pkgs.runCommand "dezimalrahmen-ok" { } "echo 'ADR-8000 eingehalten' > $out"
          else
            throw ("ADR-8000 (Dezimalrahmen) verletzt:\n  " + lib.concatStringsSep "\n  " fehler);

        # 5c. RIEGEL: Dienst-Port == Registry-Port.
        # ═══════════════════════════════════════════════════════════════
        # dezimalrahmen prueft die NUMMERN in der Registry. Dieser Check
        # prueft, dass jeder Dienst seinen Port WIRKLICH aus registry.ports
        # zieht -- nicht irgendwo einen Literal hardcodet. Ohne das koennte
        # ein Modul still von der Registry abdriften.
        # jellyfin ist ausgenommen: Port kommt aus geseedeter network.xml,
        # keine abfragbare Option.
        ports-verdrahtet =
          let
            reg = import ./lib/registry.nix { inherit lib; };
            c = self.nixosConfigurations.check-full.config;
            effektiv = {
              sonarr = c.services.sonarr.settings.server.port;
              radarr = c.services.radarr.settings.server.port;
              lidarr = c.services.lidarr.settings.server.port;
              readarr = c.services.readarr.settings.server.port;
              prowlarr = c.services.prowlarr.settings.server.port;
              sabnzbd = c.services.sabnzbd.settings.misc.port;
              navidrome = c.services.navidrome.settings.Port;
              audiobookshelf = c.services.audiobookshelf.port;
              jellyseerr = c.services.jellyseerr.port;
            };
            dienste = lib.filterAttrs (n: _: reg.ports ? ${n}) effektiv;
            drift = lib.filter (v: v != null) (
              lib.mapAttrsToList (
                name: eff:
                if eff == reg.ports.${name} then
                  null
                else
                  "${name}: Dienst-Port ${toString eff} != Registry ${toString reg.ports.${name}}"
              ) dienste
            );
          in
          if drift == [ ] then
            pkgs.runCommand "ports-verdrahtet-ok" { } "echo 'Alle Dienst-Ports == Registry' > $out"
          else
            throw ("Port-Drift zwischen Registry und Diensten:\n  " + lib.concatStringsSep "\n  " drift);

        # 6. BOOT-TEST -- VM faehrt mediNix hoch, prueft zwei leichte Dienste
        #    auf den abgeleiteten Ports/UIDs. Kette Registry->Port->UID end-to-end.
        boot = pkgs.testers.nixosTest {
          name = "medinix-boot";
          nodes.machine = {
            imports = [ ./. ];
            grapefruitMedia = {
              enable = true;
              wireFixedUids = true;
              hardware.ramGB = 4;
              navidrome.enable = true;
              audiobookshelf.enable = true;
            };
            system.stateVersion = "26.05";
          };
          testScript = ''
            machine.wait_for_unit("navidrome.service")
            machine.wait_for_unit("audiobookshelf.service")
            machine.wait_for_open_port(5530)
            machine.wait_for_open_port(5520)
            machine.succeed("test $(id -u navidrome) -eq 5053")
            machine.succeed("test $(id -u audiobookshelf) -eq 5052")
            machine.succeed("test $(getent group media | cut -d: -f3) -eq 5000")
          '';
        };

        # 7. arr-provision Python-Tests laufen in CI.
        # ═══════════════════════════════════════════════════════════════
        # Das Paket fuehrt in seiner exponierten `.tests`-Ableitung
        # `python3 -m unittest discover -s tests` aus. Referenziert es kein
        # Check, baut `nix flake check` es nie -> die Tests liefen bisher NIE
        # (provision ist auf q958 aus, also baut auch `full` das Paket nicht).
        # Dieser Check baut die Test-Ableitung -> ein API-Bruch in den
        # Sync-CLIs faellt in CI auf, nicht erst beim echten Provisioning.
        arr-provision = (pkgs.callPackage ./packages/arr-provision { }).tests;
      };

      # ── Entwicklungsumgebung ─────────────────────────────────────────────
      # nix develop -> alle Werkzeuge im PATH, ohne globale Installation.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt
          nixf-diagnose
          statix
          deadnix
          nix-tree
          jq
        ];
        shellHook = ''
          echo ""
          echo "  mediNix -- Entwicklungsumgebung"
          echo ""
          echo "    nix fmt              formatieren"
          echo "    statix check .       Anti-Patterns finden"
          echo "    deadnix .            toten Code finden"
          echo "    nix flake check      ALLES pruefen (eval + format + lint)"
          echo ""
        '';
      };
    };
}
