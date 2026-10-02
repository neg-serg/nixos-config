set -euo pipefail
export PATH="@binPath@"
HYPRCTL="/run/current-system/sw/bin/hyprctl"
while true; do
  # Prefer the instance systemd handed us, else the newest one: a compositor that died
  # leaves its /run/user/$UID/hypr/<sig>/ dir (sockets included) behind, and plain `ls -d`
  # sorts those alphabetically — it would pick the dead socket and restart-loop forever.
  run_dir="${XDG_RUNTIME_DIR:-/run/user/1000}"
  sock=""
  if [ -S "$run_dir/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-unset}/.socket2.sock" ]; then
    sock="$run_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
  else
    sock="$(ls -dt "$run_dir"/hypr/*/.socket2.sock 2>/dev/null | head -1 || true)"
  fi
  if [ -z "$sock" ]; then
    sleep 3
    continue
  fi
  # Read events; on monitor loss notify, on (re)connect ensure the daemon
  # is alive (DPMS removal can kill it) and restore the wallpapers.
  socat -u UNIX-CONNECT:"$sock" STDOUT 2>/dev/null | while read -r line; do
    case "$line" in
      monitoradded* | monitorremoved*)
        mon="${line#*>>}"
        sleep 1
        case "$line" in
          monitorremoved*)
            "$HYPRCTL" notify -1 6000 "rgb(ff5555)" "Monitor lost: $mon" >/dev/null 2>&1 || true
            ;;
          *)
            "/run/current-system/sw/bin/systemctl" --user is-active wl-daemon.service >/dev/null 2>&1 ||
              "/run/current-system/sw/bin/systemctl" --user restart wl-daemon.service
            sleep 1
            wl restore || true
            ;;
        esac
        ;;
    esac
  done
  sleep 2
done
