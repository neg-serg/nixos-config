{
  pkgs,
  lib,
  config,
  ...
}:
let
  mainUser = config.users.main.name or "neg";
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.virt = {
    docker.enable = mkBool "enable docker/podman virtualization" false;
    libvirtd.enable = mkBool "enable libvirtd (KVM/QEMU) virtualization" false;
  };

  config = {
    users.users."${mainUser}".extraGroups =
      [ "video" "render" ]
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
  };
}
