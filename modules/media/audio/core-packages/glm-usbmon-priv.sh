set -euo pipefail
# glm-usbmon-priv — root helper for USB traffic captures (usbmon).
#
# Why this needs root at all: usbmon's text and binary interfaces live in
# debugfs, which this host does not keep mounted, and reading them requires root.
# The helper mounts debugfs on a private tmpfs mountpoint for the length of a
# capture and unmounts it on stop, so nothing stays exposed between sessions.
#
# Verbs:
#   start [--bus N]   start a capture on usbmon<N> (default 0 = every bus)
#   stop              stop it, unmount debugfs, hand the pcap to the caller
#   status            one line: running/idle, pid, file, mount state
#
# Output: /var/log/glm-usbmon/capture-<timestamp>.pcap, chowned to $SUDO_UID on
# stop. No path is taken from the command line: the sudoers entry is passwordless,
# so an argument-controlled path would be a root write anywhere.

export PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/bin

DIR=/var/log/glm-usbmon
PIDFILE=$DIR/.capture.pid
# Private tmpfs mountpoint: /sys is sysfs, where the directory cannot be created.
MOUNT=/run/glm-usbmon/debugfs
USBMON=$MOUNT/usb/usbmon

die() {
  echo "glm-usbmon-priv: $*" >&2
  exit 1
}

mount_debugfs() {
  if mountpoint -q "$MOUNT"; then
    return 0
  fi
  mount -t debugfs debugfs "$MOUNT" -o rw,nosuid,nodev,noexec,mode=0700
}

unmount_debugfs() {
  if mountpoint -q "$MOUNT"; then
    umount "$MOUNT" || echo "glm-usbmon-priv: umount $MOUNT failed (device busy?)" >&2
  fi
}

stop_capture() {
  local pid out
  if [ -f "$PIDFILE" ]; then
    read -r pid out < "$PIDFILE"
    # The capture runs in its own session (setsid), so the pid is the process
    # group leader: killing the group takes dumpcap down with tshark.
    kill -TERM "-$pid" 2> /dev/null || kill -TERM "$pid" 2> /dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2> /dev/null || break
      sleep 0.2
    done
    kill -KILL "-$pid" 2> /dev/null || kill -KILL "$pid" 2> /dev/null || true
    rm -f "$PIDFILE"
    unmount_debugfs
    if [ -n "${out:-}" ] && [ -f "$out" ]; then
      chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$out"
      chmod 0640 "$out"
      echo "capture stopped: $out ($(stat -c%s "$out") bytes)"
    else
      echo "capture stopped: no file produced"
    fi
  else
    unmount_debugfs
    echo "no capture running"
  fi
}

case "${1:-}" in
  start)
    shift
    bus=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --bus)
          bus=${2:-}
          shift 2 || die "--bus needs a value"
          ;;
        *) die "unknown argument: $1" ;;
      esac
    done
    case "$bus" in
      '' | *[!0-9]*) die "--bus must be a number" ;;
    esac
    mkdir -p "$DIR"
    chmod 0755 "$DIR"
    if [ -f "$PIDFILE" ]; then
      stop_capture
    fi
    mount_debugfs
    if [ ! -e "$USBMON/${bus}u" ]; then
      die "usbmon${bus}u is missing — is the usbmon module loaded (modprobe usbmon) and CONFIG_USB_MON built?"
    fi
    out="$DIR/capture-$(date +%Y%m%d-%H%M%S).pcap"
    setsid tshark -i "usbmon${bus}" -w "$out" -q < /dev/null >> "$DIR/.capture.log" 2>&1 &
    pid=$!
    # tshark can die at once — no such interface, dumpcap refusing, debugfs not really
    # mounted. Without this check the failure stayed silent until `stop` printed
    # "no file produced", which is exactly what happened on 2026-11-02.
    sleep 0.5
    if ! kill -0 "$pid" 2> /dev/null; then
      rm -f "$PIDFILE"
      unmount_debugfs
      echo "glm-usbmon-priv: capture died immediately, last log lines:" >&2
      tail -n 5 "$DIR/.capture.log" >&2 || true
      exit 1
    fi
    echo "$pid $out" > "$PIDFILE"
    echo "capture started: usbmon${bus} -> $out (pid $pid; log $DIR/.capture.log)"
    ;;
  stop)
    stop_capture
    ;;
  status)
    if [ -f "$PIDFILE" ]; then
      read -r pid out < "$PIDFILE"
      echo "running: pid $pid -> $out"
    else
      echo "idle"
    fi
    if mountpoint -q "$MOUNT"; then
      echo "debugfs: mounted at $MOUNT"
    else
      echo "debugfs: not mounted"
    fi
    ;;
  *)
    echo "usage: glm-usbmon-priv {start [--bus N]|stop|status}" >&2
    exit 1
    ;;
esac
