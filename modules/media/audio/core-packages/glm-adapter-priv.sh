set -euo pipefail
VID=1781
PID=0e39
case "${1:-}" in
  to-vm)
    # Unbind usbhid so QEMU's usb-host passthrough re-claims the device.
    for d in /sys/bus/usb/devices/*/idVendor; do
      [ "$(cat "$d" 2> /dev/null)" = "$VID" ] || continue
      dev=${d%/idVendor}
      [ "$(cat "$dev/idProduct" 2> /dev/null)" = "$PID" ] || continue
      for i in "$dev":1.*; do
        [ -e "$i" ] || continue
        iface=${i##*/}
        if [ -L "$i/driver" ] && readlink "$i/driver" | grep -q usbhid; then
          echo "$iface" > /sys/bus/usb/drivers/usbhid/unbind 2> /dev/null || true
        fi
      done
    done
    ;;
  to-host)
    # Release from QEMU (usbfs), then bind usbhid for host genlc control.
    for d in /sys/bus/usb/devices/*/idVendor; do
      [ "$(cat "$d" 2> /dev/null)" = "$VID" ] || continue
      dev=${d%/idVendor}
      [ "$(cat "$dev/idProduct" 2> /dev/null)" = "$PID" ] || continue
      for i in "$dev":1.*; do
        [ -e "$i" ] || continue
        iface=${i##*/}
        if [ -L "$i/driver" ] && readlink "$i/driver" | grep -q usbfs; then
          echo "$iface" > /sys/bus/usb/drivers/usbfs/unbind 2> /dev/null || true
        fi
      done
      sleep 1
      for i in "$dev":1.*; do
        [ -e "$i" ] || continue
        iface=${i##*/}
        [ -L "$i/driver" ] || echo "$iface" > /sys/bus/usb/drivers/usbhid/bind 2> /dev/null || true
      done
    done
    ;;
  *)
    echo "usage: glm-adapter-priv {to-vm|to-host}" >&2
    exit 1
    ;;
esac
