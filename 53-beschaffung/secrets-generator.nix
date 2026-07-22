# ---
# id: "arr-secrets-generator"
# domain: "50"
# status: "active"
# layer: 4
# purpose: "Idempotenter API-Key-Generator fuer alle *arr-Dienste (oneshot)"
# provides: [arr-secrets-generator.service]
# requires: [grapefruitMedia.secrets.autoGenerate]
# tags: [secrets, arr, generator, systemd]
# docs:
#   - 50-core/archiv/claude-review.md (K4)
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.grapefruitMedia;
in
{
  # Review K4 (50-core/archiv/claude-review.md): Default aus -- Aktivierung nur explizit via
  # grapefruitMedia.secrets.autoGenerate.
  # K4-Fix: per-Service-Keys, korrekte Env-Var-Namen (SECTION__KEY-Konvention),
  # niemals existierende Dateien ueberschreiben (idempotent).
  config = lib.mkIf (cfg.enable && cfg.secrets.autoGenerate) {
    systemd.services.arr-secrets-generator = {
      description = "Idempotent Arr API Key Generator (per-service)";
      after = [ "local-fs.target" ];
      before = [
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
        "lidarr.service"
        "readarr.service"
        "recyclarr.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "arr-secrets-generator" ''
          set -euo pipefail
          mkdir -p ${cfg.secrets.secretsDir}
          chmod 700 ${cfg.secrets.secretsDir}

          # K4-Fix: per-Service-Key, idempotent (bestehende Dateien niemals ueberschreiben)
          gen_key() {
            local key_file="$1"
            local env_file="$2"
            local env_var="$3"
            if [ ! -f "$key_file" ]; then
              ${pkgs.openssl}/bin/openssl rand -hex 16 > "$key_file"
              chmod 600 "$key_file"
            fi
            if [ ! -f "$env_file" ]; then
              printf '%s=%s\n' "$env_var" "$(cat "$key_file")" > "$env_file"
              chmod 600 "$env_file"
            fi
          }

          gen_key "${cfg.secrets.sonarrApiKeyFile}"   "${cfg.secrets.secretsDir}/sonarr.env"   "SONARR__AUTH__APIKEY"
          gen_key "${cfg.secrets.radarrApiKeyFile}"   "${cfg.secrets.secretsDir}/radarr.env"   "RADARR__AUTH__APIKEY"
          gen_key "${cfg.secrets.prowlarrApiKeyFile}" "${cfg.secrets.secretsDir}/prowlarr.env" "PROWLARR__AUTH__APIKEY"
          gen_key "${cfg.secrets.lidarrApiKeyFile}"   "${cfg.secrets.secretsDir}/lidarr.env"   "LIDARR__AUTH__APIKEY"
          gen_key "${cfg.secrets.readarrApiKeyFile}"  "${cfg.secrets.secretsDir}/readarr.env"  "READARR__AUTH__APIKEY"
        '';
      };
    };
  };
}
