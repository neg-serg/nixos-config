{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # podman pasta --config-net copies ALL host net1 addresses (incl. the .11
  # alias) into the dockur container netns, shadowing the host alias and
  # breaking the VM's proxy path (.11:10812). Remove the shadow after the
  # container starts; idempotent when the address is absent.
  ensureVmProxyAlias = pkgs.writeShellScript "ensure-vm-proxy-alias" ''
    if ${lib.getExe pkgs.podman} container exists windows 2>/dev/null; then
      ${lib.getExe pkgs.podman} exec windows ip addr del 192.168.0.11/24 dev net1 2>/dev/null || true
    fi
  '';
in
lib.mkIf (cfg.enable or false) {
  systemd.user.services = {
    # glm-osc — OSC bridge for Genelec SAM monitors (volume/mute/power/status
    # via Python genlc over the GLM USB adapter). Kept for the OSC API, but not
    # started by default: `glm5d` owns the adapter now and a second process
    # opening it would fight the daemon for the device. Start it by hand when an
    # OSC client needs it.
    glm-osc = systemdUser.mkUserService {
      presets = [ "restartOnFailure" ];
      description = "OSC bridge for Genelec SAM monitors";
      serviceConfig = {
        ExecStart = "${pkgs.glm-osc}/bin/glm-osc-server";
        RestartSec = 5;
      };
    };

    # glm5d — the one process that owns the GLM adapter and keeps GLM's own cycle
    # (probe, lease, poll every ~0.57 s) so the monitors never drop their sessions.
    # This is the normal owner on this host: the Linux port controls the monitors
    # directly, and the Windows VM is only the occasional GLM-UI/calibration path.
    # The daemon starts at login and takes the adapter as it finds it; before
    # handing the adapter back to the VM, stop it (systemctl --user stop glm5d),
    # then attach and start the VM.
    glm5d = systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "GLM adapter owner: lease cycle, polling, Unix-socket control";
      serviceConfig = {
        ExecStart = "${pkgs.genlc}/bin/glm5d";
        RestartSec = 3;
      };
    };

    # glm-midi-relay — one-way MIDI relay to the dockur Windows VM: the VM's
    # bridge (oem/glm-midi-bridge.ps1) connects OUT to :9003 (VM-initiated TCP
    # is the only bidirectional host<->VM channel under the same-IP pasta
    # topology, unlike RTP-MIDI UDP); local glm-midi feeds 127.0.0.1:9004.
    # Not started by default: the adapter is on the host and `glm5d` controls it,
    # so the relay would only listen into an empty room. Start it with the VM.
    glm-midi-relay = systemdUser.mkUserService {
      presets = [ "restartOnFailure" ];
      description = "MIDI relay to the dockur Windows VM";
      serviceConfig = {
        # The relay is the Rust port from `packages/local-bin-tools`, installed at
        # %h/.local/bin by nix-maid — not the old Python script. Running the binary through
        # the interpreter reads ELF as source and dies on "cannot contain null bytes"
        # (2026-11-02: the unit sat in a restart loop and the MIDI path had no relay).
        ExecStart = "%h/.local/bin/glm-midi-relay";
        RestartSec = 3;
        # Log every forwarded packet (what the wheel sends) to /tmp/glm-relay.log.
        Environment = [ "GLM_RELAY_LOG=/tmp/glm-relay.log" ];
      };
    };

    # glm-adapter-auto — self-heal the GLM adapter placement with the VM as the
    # primary owner: when the VM runs without the adapter (lost on the bus,
    # replugged, left on the host), restart the VM — QEMU claims a passed-through
    # device only at its own start (no libusb hotplug inside the container).
    # Never moves the adapter back to the host; rate-limited inside the script.
    # Idempotent no-op when the adapter is already inside the VM or the VM is
    # stopped.
    glm-adapter-auto = systemdUser.mkUserService {
      presets = [ "oneshot" ];
      description = "Auto-attach the GLM adapter to the dockur VM when needed";
      serviceConfig = {
        # bash explicitly: the user-service environment has no PATH, so the
        # script's #!/usr/bin/env bash shebang would fail (status 127).
        # The default NixOS user-service PATH has only coreutils/grep/sed —
        # the script also needs awk/podman/docker/genlc/lsusb/ss/sudo.
        ExecStart = "${lib.getExe pkgs.bash} %h/.local/bin/glm-adapter auto";
        # The script starts the container itself (`podman start`), and rootless
        # podman's transient libpod-*.scope is nested under *this* service's
        # cgroup. With the default KillMode=control-group systemd reaps that
        # whole subtree the moment the oneshot exits: the guest reached
        # "Windows started successfully", then got SIGTERM 16 s after start and
        # dockur logged "QEMU exited unexpectedly" — for hours, every 60 s.
        # windows-vm.service survives the same start only because
        # RemainAfterExit=yes keeps its cgroup alive, which is why the manual
        # `systemctl --user restart windows-vm` path always worked.
        KillMode = "process";
        Environment = [
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/home/neg/.local/bin:/usr/bin:/bin"
        ];
      };
    };

    # ensure-vm-proxy-alias — one-shot cleanup for the dockur Windows VM's
    # network: podman pasta --config-net copies the host's .11 alias into the
    # container netns, shadowing it, so the VM's proxy (.11:10812) dies inside
    # the container. Re-applied on a short timer (container is started
    # manually, not as a systemd unit).
    ensure-vm-proxy-alias = systemdUser.mkUserService {
      presets = [ "oneshot" ];
      description = "Remove host .11 alias from dockur container netns";
      serviceConfig = {
        ExecStart = ensureVmProxyAlias;
      };
    };
  };

  # Cleanup for ensure-vm-proxy-alias: pasta copies the host .11 alias into the
  # container netns on every (re)start, so it has to be removed on the same
  # occasion. Not scheduled any more — that container is the Windows VM, which is
  # a manual path now; start this by hand with it.
  systemd.user.timers.ensure-vm-proxy-alias = {
    description = "VM proxy alias cleanup (manual)";
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
      Unit = "ensure-vm-proxy-alias.service";
    };
  };

  # Self-healing timer for glm-adapter-auto: it kept the adapter inside the VM
  # whenever the VM ran. Not scheduled any more: the adapter's home is the host now
  # (glm5d owns it) and this check would restart the Windows VM to claim it — the
  # VM is only started by hand for GLM's UI, with the daemon stopped first. The
  # unit stays for that path: `systemctl --user start glm-adapter-auto`.
  systemd.user.timers.glm-adapter-auto = {
    description = "Periodic GLM adapter placement check";
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
      Unit = "glm-adapter-auto.service";
    };
  };
}
