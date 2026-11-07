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
    # so systemd can't set up encrypted credentials (no /dev/tpmrm0). The whole
    # services attrset is gated: setting systemd.services.libvirtd.<x> directly
    # would leave a stub unit file in every generation even with the feature off.
    systemd.services = lib.mkIf (config.lib.neg.enabled "virt.libvirtd") {
      libvirtd.serviceConfig.LoadCredentialEncrypted = lib.mkForce [ "" ];
    };
  };
}
