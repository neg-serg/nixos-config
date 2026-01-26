{
  lib,
  config,
  pkgs,
  ...
}:
let
  systemdUser = import ../../../lib/systemd-user.nix { inherit lib; };
  port = 18888;
  # Serve from home config where surfingkeys.js is symlinked
  serveDir = "/home/neg/.config";
in
with lib;
mkIf (config.features.web.enable or false) {
  systemd.user.services.surfingkeys-server =
    let
      preset = systemdUser.mkUnitFromPresets { presets = [ "defaultWanted" ]; };
      serverScript = pkgs.writeText "sk-server.py" ''
        import http.server
        import socketserver
        import subprocess
        import os
        import sys

        PORT = ${toString port}
        DIR = "${serveDir}"

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=DIR, **kwargs)

            def do_GET(self):
                print(f"Request: {self.path}", flush=True)
                if self.path.startswith('/focus'):
                    try:
                        # Press Ctrl+L using wtype
                        subprocess.run(["${pkgs.wtype}/bin/wtype", "-M", "ctrl", "-k", "l", "-m", "ctrl"])
                        self.send_response(200)
                        self.send_header('Access-Control-Allow-Origin', '*')
                        self.end_headers()
                        self.wfile.write(b'OK')
                    except Exception as e:
                        print(f"Error: {e}", flush=True)
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(str(e).encode())

                elif self.path.startswith('/close'):
                    try:
                        # Press Ctrl+W using wtype
                        subprocess.run(["${pkgs.wtype}/bin/wtype", "-M", "ctrl", "-k", "w", "-m", "ctrl"])
                        self.send_response(200)
                        self.send_header('Access-Control-Allow-Origin', '*')
                        self.end_headers()
                        self.wfile.write(b'OK')
                    except Exception as e:
                        print(f"Error: {e}", flush=True)
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(str(e).encode())
                else:
                    return super().do_GET()

            def end_headers(self):
                self.send_header('Access-Control-Allow-Origin', '*')
                super().end_headers()

        # Allow reuse address to prevent "Address already in use" on restarts
        socketserver.TCPServer.allow_reuse_address = True

        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            print(f"Serving at port {PORT} form {DIR}")
            httpd.serve_forever()
      '';
    in
    {
      description = "HTTP server for Surfingkeys configuration";
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 -u ${serverScript}";
        Restart = "on-failure";
        RestartSec = "5";
        Slice = "background.slice";
      };
      after = preset.Unit.After or [ ] ++ [ "graphical-session.target" ];
      wants = preset.Unit.Wants or [ ] ++ [ "graphical-session.target" ];
      partOf = preset.Unit.PartOf or [ ] ++ [ "graphical-session.target" ];
      wantedBy = preset.Install.WantedBy or [ ] ++ [ "graphical-session.target" ];
    };
}
