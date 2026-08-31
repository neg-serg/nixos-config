##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of user profile state.
# Trigger: always enabled.
{
  lib,
  pkgs,
  ...
}:
let
  # glm-adapter-priv: root helper that binds/unbinds the GLM adapter's usbhid
  # interface so the adapter can move between the host and the dockur VM
  # (invoked via NOPASSWD sudo from ~/.local/bin/glm-adapter).
  glmAdapterPriv = pkgs.writeShellScriptBin "glm-adapter-priv" ''
    set -euo pipefail
    VID=1781; PID=0e39
    case "''${1:-}" in
      to-vm)
        # Unbind usbhid so QEMU's usb-host passthrough re-claims the device.
        for d in /sys/bus/usb/devices/*/idVendor; do
          [ "''$(cat "$d" 2>/dev/null)" = "$VID" ] || continue
          dev=''${d%/idVendor}
          [ "''$(cat "$dev/idProduct" 2>/dev/null)" = "$PID" ] || continue
          for i in "$dev":1.*; do
            [ -e "$i" ] || continue
            iface=''${i##*/}
            if [ -L "$i/driver" ] && readlink "$i/driver" | grep -q usbhid; then
              echo "$iface" > /sys/bus/usb/drivers/usbhid/unbind 2>/dev/null || true
            fi
          done
        done
        ;;
      to-host)
        # Release from QEMU (usbfs), then bind usbhid for host genlc control.
        for d in /sys/bus/usb/devices/*/idVendor; do
          [ "''$(cat "$d" 2>/dev/null)" = "$VID" ] || continue
          dev=''${d%/idVendor}
          [ "''$(cat "$dev/idProduct" 2>/dev/null)" = "$PID" ] || continue
          for i in "$dev":1.*; do
            [ -e "$i" ] || continue
            iface=''${i##*/}
            if [ -L "$i/driver" ] && readlink "$i/driver" | grep -q usbfs; then
              echo "$iface" > /sys/bus/usb/drivers/usbfs/unbind 2>/dev/null || true
            fi
          done
          sleep 1
          for i in "$dev":1.*; do
            [ -e "$i" ] || continue
            iface=''${i##*/}
            [ -L "$i/driver" ] || echo "$iface" > /sys/bus/usb/drivers/usbhid/bind 2>/dev/null || true
          done
        done
        ;;
      *) echo "usage: glm-adapter-priv {to-vm|to-host}" >&2; exit 1 ;;
    esac
  '';
in
{
  environment.systemPackages = lib.mkAfter [
    # -- Volume control --
    pkgs.genlc # Genelec SAM monitor volume control via GLM USB adapter
    glmAdapterPriv # root helper (NOPASSWD) that moves the GLM adapter host<->VM
    pkgs.pw-volume # minimal PipeWire volume controller for scripts

    # -- RME HDSPe --
    pkgs.hdspeconf # HDSPe matrix mixer & config (for snd-hdspe driver)
    pkgs.alsa-tools # hdspmixer, hdsploader (RME HDSPe userland tools)

    # -- GUI Patchbays --
    pkgs.coppwr # PipeWire CLI to copy/paste complex graphs
    pkgs.pwvucontrol # Qt6 PipeWire volume control (pavucontrol alternative, no GTK)
  ];

  services.udev.extraRules = ''
    KERNEL=="rtc0", GROUP="audio"
    KERNEL=="hpet", GROUP="audio"
  '';
}
