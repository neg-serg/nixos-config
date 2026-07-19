##
# Module: servers/bitcoind
# Purpose: Wire servicesProfiles.bitcoind → services.bitcoind.<instance>, firewall, logrotate, hardening,
#          and optional textfile metrics for node_exporter.
# Key options: cfg = config.servicesProfiles.bitcoind (enable, instance, dataDir, p2pPort, textfileMetrics.*)
# Dependencies: NixOS bitcoind module (services.bitcoind.*)
{
  lib,
  config,
  pkgs,
  opts,
  ...
}:
let
  cfg = config.servicesProfiles.bitcoind or { enable = false; };
  mkMetricsScript = instance: dataDir: textfileDir:
    let
      metricsFile = "${textfileDir}/bitcoind_${instance}.prom";
    in
    pkgs.writeShellScript "bitcoind-textfile-metrics.sh" ''
      set -euo pipefail
      TMPFILE="$(mktemp)"
      ts() { date +%s; }

      CLI="${lib.getExe' pkgs.bitcoind "bitcoin-cli"} -datadir ${lib.escapeShellArg dataDir}"

      # Basic info (avoid heavy calls)
      blocks=$($CLI getblockcount 2>/dev/null || echo 0)
      # headers and chain via blockchaininfo
      info=$($CLI getblockchaininfo 2>/dev/null || echo '{}')
      headers=$(printf '%s\n' "$info" | ${lib.getExe pkgs.jq} -r '.headers // 0' 2>/dev/null || echo 0)
      chain=$(printf '%s\n' "$info" | ${lib.getExe pkgs.jq} -r '.chain // "unknown"' 2>/dev/null || echo unknown)

      # Determine best block time for staleness metric
      besthash=$($CLI getbestblockhash 2>/dev/null || echo)
      if [ -n "$besthash" ]; then
        block_time=$($CLI getblockheader "$besthash" 2>/dev/null | ${lib.getExe pkgs.jq} -r '.time // 0' 2>/dev/null || echo 0)
      else
        block_time=0
      fi
      now=$(ts)
      if [ "$block_time" -gt 0 ] 2>/dev/null; then
        since=$(( now - block_time ))
      else
        since=0
      fi

      # Peer connections
      peers=$($CLI getnetworkinfo 2>/dev/null | ${lib.getExe pkgs.jq} -r '.connections // 0' 2>/dev/null || echo 0)

      cat > "$TMPFILE" <<EOF
      # HELP bitcoin_block_height Current block height as reported by bitcoind
      # TYPE bitcoin_block_height gauge
      bitcoin_block_height{instance="${instance}",chain="$chain"} $blocks
      # HELP bitcoin_headers Current header height as reported by bitcoind
      # TYPE bitcoin_headers gauge
      bitcoin_headers{instance="${instance}",chain="$chain"} $headers
      # HELP bitcoin_time_since_last_block_seconds Seconds since the best block time
      # TYPE bitcoin_time_since_last_block_seconds gauge
      bitcoin_time_since_last_block_seconds{instance="${instance}"} $since
      # HELP bitcoin_peers_connected Number of peer connections
      # TYPE bitcoin_peers_connected gauge
      bitcoin_peers_connected{instance="${instance}"} $peers
      EOF

      install -m 0644 -D "$TMPFILE" ${lib.escapeShellArg metricsFile}
      rm -f "$TMPFILE"
    '';
in
{
  options.servicesProfiles.bitcoind.textfileMetrics = {
    enable = opts.mkEnableOption "Bitcoind minimal metrics into node_exporter textfile collector";
    directory = opts.mkStrOpt {
      default = "/var/lib/node_exporter/textfile_collector";
      description = "Directory to write .prom files for node_exporter textfile collector";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.bitcoind = lib.genAttrs [ cfg.instance ] (_: {
          enable = true;
          inherit (cfg) dataDir;
          port = cfg.p2pPort;
          # Route logs to journald and keep the on-disk debug.log from growing unbounded
          # - printtoconsole=1 ensures logs go to stdout/stderr (systemd → journald → Loki/Promtail)
          # - shrinkdebugfile=1 trims debug.log on startup if present
          extraConfig = ''
            printtoconsole=1
            shrinkdebugfile=1
          '';
        });
      }
      {
        networking.firewall.allowedTCPPorts = lib.mkAfter [ cfg.p2pPort ];
      }
      {
        # Rotate bitcoind debug.log if it is written despite printtoconsole
        services.logrotate.settings."${cfg.dataDir}/debug.log" = {
          frequency = "weekly";
          rotate = 8;
          missingok = true;
          compress = true;
          delaycompress = true;
          copytruncate = true;
          size = "50M";
          # Rotate using bitcoind instance user/group to allow non-root-owned paths
          su = "bitcoind-${cfg.instance} bitcoind-${cfg.instance}";
        };
      }
      {
        systemd.services."bitcoind-${cfg.instance}".serviceConfig = {
          # Hardening
          ProtectSystem = "strict";
          PrivateTmp = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
        };
      }
      (lib.mkIf cfg.textfileMetrics.enable {
        systemd.services."bitcoind-textfile-metrics-${cfg.instance}" = {
          enable = true;
          description = "Export bitcoind minimal metrics to node_exporter textfile collector";
          serviceConfig = {
            Type = "oneshot";
            User = "bitcoind-${cfg.instance}";
            Group = "bitcoind-${cfg.instance}";
            ExecStart = mkMetricsScript cfg.instance cfg.dataDir cfg.textfileMetrics.directory;
          };
          wants = [ "bitcoind-${cfg.instance}.service" ];
          after = [ "bitcoind-${cfg.instance}.service" ];
        };

        systemd.timers."bitcoind-textfile-metrics-${cfg.instance}" = {
          enable = true;
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "30s";
            AccuracySec = "5s";
            Unit = "bitcoind-textfile-metrics-${cfg.instance}.service";
          };
        };
      })
    ]
  );
}
