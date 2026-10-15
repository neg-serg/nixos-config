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
    # via Python genlc over the GLM USB adapter, no official GLM required).
    # Listen: UDP 127.0.0.1:9000; map in docs/howto/windows-vm-dockur.md.
    glm-osc = systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "OSC bridge for Genelec SAM monitors";
      serviceConfig = {
        ExecStart = "${pkgs.glm-osc}/bin/glm-osc-server";
        RestartSec = 5;
      };
    };

    # glm-midi-relay — one-way MIDI relay to the dockur Windows VM: the VM's
    # bridge (oem/glm-midi-bridge.ps1) connects OUT to :9003 (VM-initiated TCP
    # is the only bidirectional host<->VM channel under the same-IP pasta
    # topology, unlike RTP-MIDI UDP); local glm-midi feeds 127.0.0.1:9004.
    glm-midi-relay = systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "MIDI relay to the dockur Windows VM";
      serviceConfig = {
        # Script shebang is /usr/bin/env python3, which is not in the minimal
        # user-service PATH — call the interpreter explicitly.
        ExecStart = "${lib.getExe pkgs.python3} %h/.local/bin/glm-midi-relay";
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

  # Self-healing timer for ensure-vm-proxy-alias: pasta copies the host .11
  # alias into the container netns on every (re)start, so re-check
  # periodically (cheap, idempotent).
  systemd.user.timers.ensure-vm-proxy-alias = {
    description = "Periodic VM proxy alias cleanup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
      Unit = "ensure-vm-proxy-alias.service";
    };
  };

  # Self-healing timer for glm-adapter-auto: keep the adapter inside the VM
  # whenever the VM runs (cheap idempotent check every 60s).
  systemd.user.timers.glm-adapter-auto = {
    description = "Periodic GLM adapter placement check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
      Unit = "glm-adapter-auto.service";
    };
  };
}
