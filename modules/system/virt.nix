{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.vm or { enable = false; };
  mainUser = config.users.main.name or "neg";
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.virt.docker.enable = mkBool "enable docker/podman virtualization" false;

  # Keep imports at top-level; guard heavy config below
  imports = [

  ];

  config = lib.mkIf (!cfg.enable) {
    users.users = {
      "${mainUser}" = {
        extraGroups = [
          "video"
          "render"
        ]
        ++ (lib.optional (config.features.virt.docker.enable or false) "docker"); # Add docker group here if needed, usually 'docker' group is for real docker
      };
    };
    virtualisation = lib.mkMerge [
      {
        containers.enable = true;
        libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm; # Generic and open source machine emulator and virtualizer
            runAsRoot = true;
            vhostUserPackages = [ pkgs.virtiofsd ]; # vhost-user virtio-fs device backend written in Rust
            swtpm.enable = true;
          };
        };
      }
      (lib.mkIf (config.features.virt.docker.enable or false) {
        podman = {
          enable = true;
          dockerCompat = lib.mkDefault true; # Create a `docker` alias for podman, to use it as a drop-in replacement
          dockerSocket.enable = lib.mkDefault true; # Create docker alias for compatibility
          defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
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
      })
    ];

    programs.virt-manager.enable = true;
    services.spice-webdavd.enable = true;
  };
}
