{
  pkgs,
  lib,
  ...
}:
let
  podman = lib.getExe pkgs.podman;

  # The dockur VM is the primary Genelec GLM control path (host-side genlc /
  # glm-osc stays a manual reserve), so it starts with the machine. QEMU opens a
  # passed-through device only when the QEMU process starts — libusb hotplug
  # events never reach the container (its own netns, no /run/udev) — so the GLM
  # adapter (1781:0e39) has to be on the bus before the container starts.
  # Starting without it would leave the VM unable to control the monitors until
  # the next restart, hence the wait.
  waitForAdapter = pkgs.writeShellScript "windows-vm-wait-adapter" ''
    for _ in $(seq 1 60); do
      for dev in /sys/bus/usb/devices/*/idVendor; do
        [ -r "$dev" ] || continue
        read -r vid < "$dev" || continue
        [ "$vid" = "1781" ] || continue
        read -r pid < "''${dev%/idVendor}/idProduct" || continue
        [ "$pid" = "0e39" ] && exit 0
      done
      sleep 1
    done
    # Start anyway: glm-adapter-auto restarts the VM once the adapter shows up.
    exit 0
  '';

  # pasta runs with --config-net, which copies the host uplink's whole address
  # list into the container's netns — including the 192.168.2.88 alias the guest
  # needs to reach the host on (:9003 MIDI relay, 10811/10812 VM proxy). While
  # that alias is present inside the container the guest's packets are answered
  # by the container itself — "Connection refused" — so the MIDI bridge holds a
  # dead TCP connection (still printing "connected to host relay") and every CC
  # disappears. pasta recreates the alias on every start, so drop it right after
  # each one (the same script glm-adapter runs after its own VM restarts).
  netfix = pkgs.writeShellScript "windows-vm-netfix" ''
    export PODMAN=${podman}
    ${builtins.readFile ../../../packages/local-bin/scripts/glm-vm-netfix}
  '';

  startVm = pkgs.writeShellScript "windows-vm-start" ''
    if ! ${podman} container exists windows; then
      echo "container 'windows' does not exist — recreate it (docs/howto/windows-vm-dockur.md)" >&2
      exit 1
    fi
    if ${podman} ps --format '{{.Names}}' | grep -qx windows; then
      echo "windows is already running"
      exit 0
    fi
    ${podman} start windows
  '';
in
{
  # Rootless podman runs under the user manager, so the VM is a user unit. The
  # glm-adapter self-heal path reports through the Alertmanager Telegram bridge
  # on 127.0.0.1:9094 (see packages/local-bin/scripts/glm-adapter, notify*).
  systemd.user.services.windows-vm = {
    description = "dockur Windows VM (GLM control path)";
    after = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = waitForAdapter;
      ExecStart = startVm;
      ExecStartPost = netfix;
      # `podman start` returns as soon as QEMU is detached; the guest keeps booting.
      TimeoutStartSec = 180;
    };
  };
}
