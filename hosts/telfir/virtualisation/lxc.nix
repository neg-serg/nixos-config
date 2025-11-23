{
  pkgs,
  ...
}: {
  # LXC host-side configuration for the zero-sandbox container.
  #
  # This module:
  # - mounts the existing btrfs image /zero/sandbox/d1-btrfs450.img
  #   at /zero/sandbox/mnt-d1;
  # - enables LXC and installs the userspace tools;
  # - provides a systemd service to run the zero-sandbox container.
  #
  # The container rootfs and base config should be created once manually, e.g.:
  #
  #   sudo nix shell nixpkgs#lxc -c \
  #     lxc-create -n zero-sandbox -P /zero/sandbox/mnt-d1 \
  #       -t download -- -d ubuntu -r noble -a amd64
  #
  # After that, edit /zero/sandbox/mnt-d1/zero-sandbox/config and add:
  #
  #   lxc.cgroup2.memory.max = 48G
  #   lxc.mount.entry = /zero zero none bind,ro,create=dir 0 0

  virtualisation.lxc.enable = true;

  environment.systemPackages = [
    pkgs.lxc # LXC userspace tools (lxc-start, lxc-attach, etc.)
    pkgs.wget # HTTP(S) downloader for LXC templates
  ];

  # Ensure the parent directory for the sandbox exists.
  systemd.tmpfiles.rules = [
    "d /zero/sandbox 0755 root root -"
  ];

  # Mount the 450 GiB btrfs image as a loop filesystem.
  fileSystems."/zero/sandbox/mnt-d1" = {
    device = "/zero/sandbox/d1-btrfs450.img";
    fsType = "btrfs";
    options = [
      "loop"
      "nofail"
    ];
  };

  # Systemd unit to manage the zero-sandbox LXC container.
  systemd.services."lxc-zero-sandbox" = {
    description = "LXC container zero-sandbox on /zero/sandbox/d1-btrfs450.img";
    after = [
      "network.target"
      "local-fs.target"
    ];
    requires = [
      "local-fs.target"
    ];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.lxc}/bin/lxc-start -n zero-sandbox -P /zero/sandbox/mnt-d1 -d";
      ExecStop = "${pkgs.lxc}/bin/lxc-stop -n zero-sandbox -P /zero/sandbox/mnt-d1";
    };

    unitConfig.RequiresMountsFor = ["/zero/sandbox/mnt-d1"];
  };
}
