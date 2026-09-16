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

  systemdUser = import ../../lib/systemd-user.nix { inherit lib; };

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
    text = builtins.readFile (
      pkgs.replaceVars ./notify/netops-vpn-watch.sh {
        sender = config.odin.telegram.sender;
        curl = pkgs.curl;
        systemd = pkgs.systemd;
        inherit socksProxy;
      }
    );
  };

  # Part B: weekly "system flake is stale" reminder on the local ntfy server.
  staleScript = pkgs.writeShellApplication {
    name = "ntfy-system-stale";
    runtimeInputs = [
      pkgs.curl # ntfy POST
      pkgs.coreutils # date arithmetic
      pkgs.git # read last flake.lock-touching commit date
    ];
    text = builtins.readFile (
      pkgs.replaceVars ./notify/netops-stale.sh {
        curl = pkgs.curl;
      }
    );
  };
in
mkMerge [
  # ---- Part A: telegram-vpn-watch (gated on the telegram sops file) ----
  (mkIf config.odin.telegram.enable (
    systemdUser.mkOneshotTimer {
      name = "telegram-vpn-watch";
      description = "Notify Telegram on WireGuard up/public-IP changes";
      timerDescription = "Watch the WireGuard tunnel and public IP every 10 minutes";
      script = lib.getExe vpnWatchScript;
      onCalendar = "*-*-* *:0/10:00";
      restartSec = 30;
      stateDirectory = "telegram-vpn-watch";
    }
  ))

  # ---- Part B: ntfy-system-stale (gated on the net-health feature flag that
  # supplies the local ntfy server on :2586) ----
  (mkIf (config.features.net.netHealth.enable or false) (
    systemdUser.mkOneshotTimer {
      name = "ntfy-system-stale";
      description = "Remind to nix flake update when flake.lock is stale";
      timerDescription = "Weekly stale-flake reminder";
      script = lib.getExe staleScript;
      onCalendar = "Mon *-*-* 10:00:00";
    }
  ))
]
