{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.profiles.vm or {enable = false;};
  mainUser = config.users.main.name or "neg";
in {
  # Keep imports at top-level; guard heavy config below
  imports = [./virt/pkgs.nix];

  config = lib.mkIf (!cfg.enable) {
    users.users = {
      "${mainUser}" = {
        extraGroups = ["video" "render"];
      };
    };
    virtualisation = {
      containers.enable = true;

      podman = {
        enable = true;
        dockerCompat = true; # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerSocket.enable = true; # Create docker alias for compatibility
        defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
      };

      oci-containers.backend = "podman";

      docker = {
        enable = false;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = ["--all"];
        };
      };

      libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = true;
          vhostUserPackages = [pkgs.virtiofsd];
          swtpm.enable = true;
          ovmf = {
            enable = true;
            packages = [
              (pkgs.OVMF.override {
                secureBoot = true;
                tpmSupport = true;
              }).fd
            ];
          };
        };
      };
    };

    programs.virt-manager.enable = true;
    services.spice-webdavd.enable = true;
  };
}
