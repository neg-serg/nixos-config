{
  pkgs,
  lib,
  config,
  ...
}:
let
  mainUser = config.users.main.name or "neg";
in {
  config = {
    users.users."${mainUser}".extraGroups = [
      "video"
      "render"
    ]
    ++ lib.optional (config.features.virt.docker.enable or false) "docker";

    virtualisation = {
      containers.enable = true;

      libvirtd = lib.mkIf (config.features.virt.libvirtd.enable or false) {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = true;
          vhostUserPackages = [ pkgs.virtiofsd ];
          swtpm.enable = false;
        };
      };
    }
    // lib.optionalAttrs (config.features.virt.docker.enable or false) {
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
  };
}
