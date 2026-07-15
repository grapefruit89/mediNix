{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.grapefruitMedia;
in
{
  config = mkIf cfg.enable {
    systemd.services.media-secrets-portal = {
      description = "Media Secrets Portal UI Daemon";
      after = [ "network.target" "arr-secrets-generator.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 -c '
import http.server
import socketserver
import os
import urllib.parse

PORT = ${toString cfg.ports.secrets-portal}
SECRETS_DIR = \"${cfg.secrets.secretsDir}\"
USENET_FILE = \"${cfg.secrets.usenetFile}\"
VPN_FILE = \"${cfg.secrets.vpnFile}\"
INDEXERS_FILE = \"${cfg.secrets.indexersFile}\"

class PortalHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header(\"Content-type\", \"text/html\")
        self.end_headers()
        self.wfile.write(b\"<html><body><h1>Secrets Portal UI</h1></body></html>\")

    def do_POST(self):
        content_length = int(self.headers[\"Content-Length\"])
        post_data = self.rfile.read(content_length)
        params = urllib.parse.parse_qs(post_data.decode(\"utf-8\"))
        
        os.makedirs(SECRETS_DIR, exist_ok=True)
        if self.path == \"/save-usenet\":
            key = params.get(\"usenet_key\", [\"\"])[0]
            with open(USENET_FILE, \"w\") as f:
                f.write(f\"USENET_KEY={key}\\n\")
            os.chmod(USENET_FILE, 0o600)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b\"Saved\")
        elif self.path == \"/save-vpn\":
            key = params.get(\"vpn_key\", [\"\"])[0]
            with open(VPN_FILE, \"w\") as f:
                f.write(f\"VPN_KEY={key}\\n\")
            os.chmod(VPN_FILE, 0o600)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b\"Saved\")
        elif self.path == \"/save-indexers\":
            key = params.get(\"indexer_key\", [\"\"])[0]
            with open(INDEXERS_FILE, \"w\") as f:
                f.write(f\"INDEXER_KEY={key}\\n\")
            os.chmod(INDEXERS_FILE, 0o600)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b\"Saved\")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer((\"127.0.0.1\", PORT), PortalHandler) as httpd:
    httpd.serve_forever()
'";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.secrets.secretsDir ];
        User = "nobody";
      };
    };

    # Systemd path watchdogs for portal credentials
    systemd.paths.media-secrets-watchdog = {
      description = "Watchdog for Usenet/Arr Secrets changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = [
          cfg.secrets.usenetFile
          cfg.secrets.vpnFile
          cfg.secrets.indexersFile
        ];
        Unit = "media-secrets-reload.service";
      };
    };

    systemd.services.media-secrets-reload = {
      description = "Reload affected media services on secrets change";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "media-secrets-reload" ''
          ${pkgs.systemd}/bin/systemctl reload-or-restart sabnzbd.service prowlarr.service || true
        '';
      };
    };
  };
}
