{ pkgs, lib, ... }: {
  imports = [
    ./hardware.nix
    ../../modules/system
    ../../modules/nix
    ../../modules/security
    ../../modules/roles
  ];

  networking.hostName = "nixos";
  system.stateVersion = "25.05";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.qemuGuest.enable = true;

  security.sudo.wheelNeedsPassword = false;

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx7F9KuTtPsLj9UVtUQ9ZrXUebjCMKuKZcyZWzg2RHf serg.zorg@gmail.com"
    ];
  };

  # 16GB swap
  swapDevices = [{ device = "/swapfile"; size = 16384; }];

  # Limit build parallelism to avoid OOM (V8/nodejs needs ~2GB per compiler)
  nix.settings = {
    max-jobs = 4;
    cores = 4;
  };

  # Disable doc generation (pulls nodejs/furo)
  documentation.doc.enable = lib.mkForce false;
  documentation.info.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;

  environment.systemPackages = [ pkgs.git ];
  users.users.root.hashedPassword = "!";
}
