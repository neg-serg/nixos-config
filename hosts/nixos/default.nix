{ pkgs, ... }: {
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

  users.users.root.hashedPassword = "!";
}
