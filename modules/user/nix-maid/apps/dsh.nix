{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;
  # Wrap dsh so it loads DEEPSEEK_API_KEY from the sops secret itself, rather
  # than relying on shell init — works even from a terminal opened before the
  # secret was wired (a shell only sources .zshenv at startup).
  dshWrapped = pkgs.writeShellScriptBin "dsh" ''
    export DEEPSEEK_API_KEY="''${DEEPSEEK_API_KEY:-$(cat /run/secrets/deepseek-api 2>/dev/null)}"
    exec ${pkgs.neg.dsh}/bin/dsh "$@"
  '';
in
{
  # DeepSeek Harness (dsh) — agent harness, everything is a plugin.
  # Web UI: desktop at http://127.0.0.1:3080. For the phone remote panel
  # (dsh-remote-web-ui) a narrow LAN socket (systemd-socket-proxyd) forwards
  # 192.168.2.87:3080 → 127.0.0.1:3080, so dsh itself never binds anything
  # wider than loopback. The firewall opens port 3080 ONLY on the LAN uplink
  # (net1) — nothing else is exposed.
  networking.firewall.interfaces.net1.allowedTCPPorts = [ 3080 ];

  # LAN phone pairing socket: listens exactly on the LAN address. The /api
  # trust fence accepts this authority via the web-runtime override in
  # dsh-market.nix; the panel URL comes from the remote-web-ui
  # `publicBaseUrl` setting (settings.yaml).
  systemd.user.sockets.dsh-lan-proxy = {
    enable = true;
    description = "dsh LAN phone proxy socket (192.168.2.87:3080)";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "192.168.2.87:3080";
    };
  };

  systemd.user.services.dsh-lan-proxy = {
    enable = true;
    description = "dsh LAN phone proxy — forwards 192.168.2.87:3080 to 127.0.0.1:3080";
    after = [ "dsh.service" ];
    wants = [ "dsh.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "/run/current-system/sw/lib/systemd/systemd-socket-proxyd 127.0.0.1:3080";
    };
  };

  systemd.user.services.dsh = {
    enable = true;
    description = "DeepSeek Harness (dsh) — agent harness Web UI";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    environment = {
      # The Landlock sandbox (landlock-run) execs wrapped commands via
      # execvp, which needs the system PATH. systemd's default user-service
      # PATH lacks /run/current-system/sw/bin, so sandboxed tool calls fail
      # with "landlock-run: exec failed: No such file or directory".
      PATH = lib.mkForce "/run/current-system/sw/bin:/run/wrappers/bin:/usr/local/bin:/usr/bin:/bin";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = homeDir;
      # HMR plugin requires node --expose-internals (not allowed in NODE_OPTIONS)
      ExecStart = "${lib.getExe pkgs.nodejs} --expose-internals ${pkgs.neg.dsh}/lib/node_modules/@deepseek-ai/dsh/lib/bin.js web";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # Install the dsh CLI into the environment (PATH).
  environment.systemPackages = [
    dshWrapped # DeepSeek Harness agent CLI (dsh) — wrapped to load the DeepSeek API key
    pkgs.pnpm # pnpm package manager (used by `dsh plugin --profile <name> add`)
    pkgs.gnumake # make — required by node-gyp when pnpm builds node-pty (SSH terminal) in the dsh web profile
  ];
}
