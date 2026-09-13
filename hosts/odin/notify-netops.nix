# notify-netops.nix — two small operational notifiers for host "odin".
#
# (A) telegram-vpn-watch (oneshot + timer, every 10 min): watches the on-demand
#     WireGuard tunnel (wg-quick-vpn-odin) and the public egress IP. Sends a
#     Telegram message on a down->up transition ("VPN поднят") and on a public
#     IP change while the tunnel stays up. Gated on config.odin.telegram.enable
#     (see hosts/odin/telegram.nix).
# (B) ntfy-system-stale (oneshot + timer, weekly Monday 10:00): reminds to run
#     `nix flake update` when the last commit that touched flake.lock is older
#     than 14 days. Posts an info/low ntfy message to the local server topic
#     `system` (net-health feature provides the ntfy server). Gated on the
#     same feature flag that enables net-health / ntfy.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkMerge;

  # Shared facts: the telegram sender must egress via the user sing-box socks
  # proxy (127.0.0.1:10808), which starts at login, so keep retrying ~1 min.
  socksProxy = "socks5h://127.0.0.1:10808";

  # Part A: VPN/public-IP watcher. State (last notified IP + down marker) lives
  # under /var/lib/telegram-vpn-watch (StateDirectory). Reads sops token/chat.
  vpnWatchScript = pkgs.writeShellApplication {
    name = "telegram-vpn-watch";
    runtimeInputs = [
      pkgs.curl # public-IP fetch (delivery goes through the shared sender)
      pkgs.coreutils # cat, rm, sleep for retry loop
      pkgs.systemd # systemctl tunnel state probe
    ];
    text = ''
      set -euo pipefail

      STATE=/var/lib/telegram-vpn-watch
      IP_FILE="$STATE/ip.txt"
      DOWN_MARKER="$STATE/down"
      SYSCTL=${pkgs.systemd}/bin/systemctl
      CURL=${pkgs.curl}/bin/curl
      SEND=${config.odin.telegram.sender}/bin/telegram-send

      # Delivery failure is not a unit failure; the shared sender retries
      # ~1 min through the socks proxy on its own.
      send() { # $1 = message text
        "$SEND" "$1" || true
      }

      # 1. Down (stopped manually / inactive) is a normal action here — record
      #    the down edge and stay silent (no Telegram spam).
      if ! $SYSCTL is-active --quiet wg-quick-vpn-odin; then
        touch "$DOWN_MARKER"
        exit 0
      fi

      # 2. Tunnel is active. Fetch the public egress IP; when the tunnel is up
      #    the default route already egresses through it. Fall back to the
      #    socks proxy variant if the direct fetch fails.
      ip=$($CURL -sf -m 10 https://api.ipify.org || true)
      if [ -z "$ip" ]; then
        ip=$($CURL -sf -m 10 --proxy ${socksProxy} https://api.ipify.org || true)
      fi
      if [ -z "$ip" ]; then
        echo "telegram-vpn-watch: could not fetch public IP" >&2
        exit 0 # leave state untouched; retry next tick
      fi

      prev=""
      if [ -f "$IP_FILE" ]; then
        prev=$(cat "$IP_FILE")
      fi

      # 3. Down->up transition: notify "поднят".
      if [ -f "$DOWN_MARKER" ]; then
        rm -f "$DOWN_MARKER"
        send "🌐 VPN поднят (IP: $ip)"
        printf '%s\n' "$ip" > "$IP_FILE"
        exit 0
      fi

      # First observation while already up (fresh state): record, notify once.
      if [ -z "$prev" ]; then
        send "🌐 VPN поднят (IP: $ip)"
        printf '%s\n' "$ip" > "$IP_FILE"
        exit 0
      fi

      # IP changed while the tunnel stayed up: notify, keep the same marker.
      if [ "$prev" != "$ip" ]; then
        send "🌐 VPN: публичный IP сменился $prev -> $ip"
      fi
      printf '%s\n' "$ip" > "$IP_FILE"
      exit 0
    '';
  };

  # Part B: weekly "system flake is stale" reminder on the local ntfy server.
  staleScript = pkgs.writeShellApplication {
    name = "ntfy-system-stale";
    runtimeInputs = [
      pkgs.curl # ntfy POST
      pkgs.coreutils # date arithmetic
      pkgs.git # read last flake.lock-touching commit date
    ];
    text = ''
      set -euo pipefail

      CURL=${pkgs.curl}/bin/curl
      NTFY_URL="http://127.0.0.1:2586/system"

      # 1. Age (days) of the last commit that touched flake.lock.
      last=$(git -C /etc/nixos log -1 --format=%cs -- flake.lock || true)
      if [ -z "$last" ]; then
        echo "ntfy-system-stale: no flake.lock commit date found" >&2
        exit 0
      fi
      last_epoch=$(date -d "$last" +%s)
      now_epoch=$(date +%s)
      age=$(( (now_epoch - last_epoch) / 86400 ))

      # 2. Fresh enough -> silent exit.
      if [ "$age" -le 14 ]; then
        exit 0
      fi

      # 3. Post an info/low reminder to the local ntfy `system` topic.
      msg="Флейк не обновлялся $age дней (последний раз $last). Пора nix flake update."
      $CURL -sS -m 5 -X POST \
        -H "Title: Система" \
        -H "Priority: low" \
        --data "$msg" \
        "$NTFY_URL" >/dev/null 2>&1 || true
      exit 0
    '';
  };
in
mkMerge [
  # ---- Part A: telegram-vpn-watch (gated on the telegram sops file) ----
  (mkIf config.odin.telegram.enable {
    systemd.services."telegram-vpn-watch" = {
      description = "Notify Telegram on WireGuard up/public-IP changes";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "telegram-vpn-watch";
        ExecStart = "${lib.getExe vpnWatchScript}";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    systemd.timers."telegram-vpn-watch" = {
      description = "Watch the WireGuard tunnel and public IP every 10 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:0/10:00";
        Unit = "telegram-vpn-watch.service";
      };
    };
  })

  # ---- Part B: ntfy-system-stale (gated on the net-health feature flag that
  # supplies the local ntfy server on :2586) ----
  (mkIf (config.features.net.netHealth.enable or false) {
    systemd.services."ntfy-system-stale" = {
      description = "Remind to nix flake update when flake.lock is stale";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe staleScript}";
        Restart = "on-failure";
        RestartSec = 60;
      };
    };

    systemd.timers."ntfy-system-stale" = {
      description = "Weekly stale-flake reminder";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon *-*-* 10:00:00";
        Unit = "ntfy-system-stale.service";
      };
    };
  })
]
