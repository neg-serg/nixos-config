{
  pkgs,
  lib,
  config,
  ...
}:
let
  mainUser = config.lib.neg.mainUser;
in
{
  config = {
    users.users."${mainUser}".extraGroups = [
      "video"
      "render"
    ]
    ++ lib.optional (config.lib.neg.enabled "virt.docker") "docker";

    virtualisation = {
      containers.enable = true;

      libvirtd = lib.mkIf (config.lib.neg.enabled "virt.libvirtd") {
        enable = true;
        firewallBackend = "nftables";
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = true;
          vhostUserPackages = [ pkgs.virtiofsd ];
          swtpm.enable = false;
        };
      };
    }
    // lib.optionalAttrs (config.lib.neg.enabled "virt.docker") {
      podman = {
        enable = true;
        dockerCompat = lib.mkDefault true;
        dockerSocket.enable = lib.mkDefault true;
        defaultNetwork.settings.dns_enabled = true;
      };
      oci-containers.backend = "podman";
      docker = {
        enable = lib.mkDefault false;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };
      };
    };

    # Clear LoadCredentialEncrypted — TPM2 is disabled on this host,
    # so systemd can't set up encrypted credentials (no /dev/tpmrm0).
    systemd.services.libvirtd.serviceConfig.LoadCredentialEncrypted = lib.mkForce [ "" ];

    # RDPWindows VM — auto-defined on boot via systemd oneshot
    systemd.services."virsh-define-RDPWindows" = lib.mkIf (config.lib.neg.enabled "virt.libvirtd") {
      description = "Define RDPWindows libvirt domain from XML";
      after = [ "libvirtd.service" ];
      wants = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/var/lib/libvirt/images/RDPWindows.qcow2";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "libvirt/images libvirt/iso";
      };
      path = [
        pkgs.libvirt
        pkgs.qemu_kvm # KVM virtual machines
        pkgs.diffutils # `cmp -s` in the fast path below: a unit's PATH is only
        # what `path` lists, so a bare cmp died with "command not found", the
        # fast path never matched, and every boot took the virsh define/autostart
        # branch (~0.9 s on the 2026-10-01 boot, plus a ~1.5 s socket wait).
      ];
      script = ''
        # Fast path: the domain XML and its autostart link are on disk and the
        # source that produced them has not changed since. Skipping the `virsh`
        # calls matters: the first one blocks on libvirtd's socket for up to
        # ~1.5 s and this oneshot sits in the boot critical chain (multi-user.target
        # waits for it: 7.18s + 1.59s on the 2026-09-27 boot, 0.9 s on 2026-10-01).
        # The stamp is what makes the comparison meaningful: libvirt stores the XML
        # in its own expanded form (5372 B / 124 lines for the 2004 B / 60-line
        # source), so comparing that file with the source — the original check —
        # could never match: the fast path was dead on arrival, and the missing
        # `cmp` in the unit's PATH only hid it. Missing domain or link (deleted by
        # hand, fresh libvirt state) still falls through to the repair below.
        src=${config.lib.neg.path "files/virt/RDPWindows.xml"}
        stamp=/var/lib/libvirt/.nix-RDPWindows.xml.defined
        if [[ -e /var/lib/libvirt/qemu/RDPWindows.xml \
              && -e /var/lib/libvirt/qemu/autostart/RDPWindows.xml ]] \
           && cmp -s "$stamp" "$src"; then
          exit 0
        fi
        if ! virsh dominfo RDPWindows >/dev/null 2>&1; then
          virsh define "$src"
        fi
        virsh autostart RDPWindows
        # Record the source that produced the current definition: the next boot
        # (or rebuild) can then skip the virsh calls entirely.
        install -m 600 "$src" "$stamp"
      '';
    };

  };
}
