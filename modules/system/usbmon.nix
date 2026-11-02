##
# Module: system/usbmon
# Purpose: USB traffic capture (usbmon) available on demand, without mounting
#   debugfs at boot.
#
# The chain, in the order it applies:
#   - `CONFIG_USB_MON=m` — `modules/system/kernel/overlay.config`, block H23.
#   - preload — `hosts/trantor/hardware/kernel.nix` loads `usbmon` before
#     `lockKernelModules` sets `kernel.modules_disabled=1`.
#   - debugfs — the module is useless without it, because usbmon exposes itself
#     only through debugfs (`<debugfs>/usb/usbmon`). Nothing is mounted here: the
#     mountpoint just exists so the root helper can mount it for one capture
#     (see `modules/media/audio/core-packages/glm-usbmon-priv.sh`).
#     The mountpoint is on tmpfs, NOT the customary `/sys/kernel/debug`: `/sys` is
#     sysfs, where userspace cannot create the directory (`mkdir` fails, tmpfiles
#     silently skips it), and debugfs does not care where it is mounted — usbmon's
#     files show up under whatever directory it is attached to.
#   - privileges — `glm-usbmon-priv` is NOPASSWD in `modules/security/default.nix`;
#     it validates its own verbs, mounts and unmounts debugfs itself, and writes
#     only under `/var/log/glm-usbmon`.
#
# Why it exists at all: the Genelec GLM/GNet wire protocol is undocumented, so
# the only way to learn what the official GLM sends to the adapter is to watch
# the USB traffic (.agent/plans/2026-11-02-glm5-linux-port.md, task T1).
{ ... }:
{
  systemd.tmpfiles.rules = [
    # Private mountpoint for the on-demand debugfs mount (tmpfs, 0700): a stray
    # mount stays unreadable to everyone but root.
    "d /run/glm-usbmon 0700 root root - -"
    "d /run/glm-usbmon/debugfs 0700 root root - -"
    # Capture directory: written by the root helper, chowned to the caller on stop.
    # 0755, not 0700: the helper hands the pcap to the invoking user (0640, owned by
    # them), and a 0700 parent made that chown useless — the owner still could not
    # reach the file, because traversal needs +x on the directory.
    "d /var/log/glm-usbmon 0755 root root - -"
  ];
}
