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

  # dsh-watchdog: the web service can end up dead with a straggler node still
  # holding port 3080 — plain 'systemctl --user restart' fails with "Failed to
  # kill control group: Operation not permitted" whenever root processes (e.g.
  # 'sudo nixos-rebuild' typed into a web terminal) sit in the service cgroup,
  # and Restart=on-failure never fires for a unit stop. This timer-driven check
  # brings the unit back: if it is not active, or it is active but port 3080 is
  # dead, stragglers are killed and the service is (re)started via dsh-restart.
  watchdogScript = pkgs.writeShellScript "dsh-watchdog" ''
    export PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/local/bin:/usr/bin:/bin
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    state="$(systemctl --user is-active dsh.service 2>/dev/null || true)"
    case "$state" in
      active)
        if curl -sS --max-time 5 -o /dev/null http://127.0.0.1:3080/; then
          exit 0
        fi
        # Active but not serving: give a freshly started instance a minute to
        # bind the port before forcing a restart.
        entered="$(systemctl --user show -p ActiveEnterTimestamp --value dsh.service 2>/dev/null || true)"
        if [ -n "$entered" ]; then
          entered_ts="$(date -d "$entered" +%s 2>/dev/null || echo 0)"
          if [ "$(( $(date +%s) - entered_ts ))" -lt 60 ]; then
            exit 0
          fi
        fi
        echo "dsh-watchdog: dsh.service active but port 3080 dead — restarting" >&2
        exec ${pkgs.neg.dsh-restart}/bin/dsh-restart
        ;;
      activating|deactivating|reloading)
        exit 0
        ;;
      *)
        echo "dsh-watchdog: dsh.service is $state — cleaning stragglers and starting" >&2
        pkill -f '/lib/bin\.js web' 2>/dev/null || true
        sleep 1
        systemctl --user start dsh.service 2>/dev/null || true
        ;;
    esac
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
    # A failed stop/start cycle (root processes in the cgroup, port 3080 held
    # by a straggler) used to trip the default 5 starts / 10s limit and leave
    # the unit failed — the dsh-watchdog timer then had nothing to restart.
    # 10 tries / 60s gives the watchdog and the ensure scripts room to work.
    startLimitIntervalSec = 60;
    startLimitBurst = 10;
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

  # Timer + oneshot: periodic health check for dsh.service (see watchdogScript).
  systemd.user.services.dsh-watchdog = {
    enable = true;
    description = "dsh web watchdog — check dsh.service health, restart if dead";
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = watchdogScript;
    };
  };

  systemd.user.timers.dsh-watchdog = {
    enable = true;
    description = "dsh web watchdog — periodic health check of dsh.service";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "45s";
      Persistent = true;
    };
  };

  # Install the dsh CLI into the environment (PATH).
  environment.systemPackages = [
    dshWrapped # DeepSeek Harness agent CLI (dsh) — wrapped to load the DeepSeek API key
    pkgs.pnpm # pnpm package manager (used by `dsh plugin --profile <name> add`)
    pkgs.gnumake # make — required by node-gyp when pnpm builds node-pty (SSH terminal) in the dsh web profile
  ];
}
