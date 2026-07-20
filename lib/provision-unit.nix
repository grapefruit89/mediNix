# ---
# id: "provision-unit"
# domain: "50"
# status: "active"
# layer: 5
# role: lib
# purpose: "Einheitlicher oneshot-Unit-Bauer fuer die Provisionierungs-Schritte"
# tags: [lib, provisioning, systemd]
# docs:
#   - modules/50-media/docs/adr/5037-daten-statt-code.md
# ---
#
# Warum es diesen Helfer gibt (ADR-5037, Teil 2):
# Der identische serviceConfig-Block stand vorher in allen acht Task-Dateien.
# Das ist kein Korrektheitsproblem, sondern eine Wartungsfalle: Die geplante
# Haertung dieser Units (Issue #49-Follow-up) haette acht Fundstellen gebraucht,
# mit der Gefahr, eine zu vergessen.
#
# ==> HIER wird kuenftig gehaertet. Eine Stelle fuer alle Provisionierungs-Units.
#
# Warum die Units als root laufen: sie schreiben in die App-Configs
# (/var/lib/<svc>/config.xml) und starten Dienste ueber systemctl neu.
# Sandboxing ist moeglich, muss aber am echten System erprobt werden --
# bewusster Follow-up, nicht vergessen.
{
  # deadnix hat hier zu Recht gemeldet, dass lib nicht verwendet wird.
  # Die Ellipse statt eines leeren Musters, weil Aufrufer weiterhin
  # { inherit lib; } uebergeben -- ein Attributset-Muster ohne ... ist in Nix
  # strikt und lehnt unerwartete Argumente mit
  #   "function called with unexpected argument 'lib'"
  # ab. Ellipse = ehrlich (wird nicht gebraucht) und tolerant zugleich.
  ...
}:
{
  # mkProvisionUnit :: attrs -> nixos-config-fragment
  #
  # Erzeugt genau eine oneshot-Unit mit der einheitlichen Provisionierungs-Politik.
  # Der Aufrufer liefert nur, was den Schritt tatsaechlich unterscheidet:
  # Name, Beschreibung, Abhaengigkeiten, Umgebung, Skript.
  mkProvisionUnit =
    {
      name,
      description,
      after ? [ ],
      wants ? [ ],
      wantedBy ? [ "multi-user.target" ],
      environment,
      script,
      # Selten noetig -- profiles.nix braucht mehr Zeit, weil es auf Recyclarr wartet.
      restartSec ? "30s",
      startLimitBurst ? 3,
      startLimitIntervalSec ? 600,
    }:
    {
      systemd.services.${name} = {
        inherit
          description
          after
          wants
          wantedBy
          environment
          script
          startLimitIntervalSec
          ;

        serviceConfig = {
          Type = "oneshot";
          # Verhindert, dass der Schritt bei jedem Neustart erneut laeuft.
          RemainAfterExit = true;
          User = "root";
          Restart = "on-failure";
          RestartSec = restartSec;
          StartLimitBurst = startLimitBurst;
        };
      };
    };
}
