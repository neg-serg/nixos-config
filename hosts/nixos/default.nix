{ pkgs, lib, ... }: {
  imports = [
    ./hardware.nix
    ../../modules/system
    ../../modules/nix
    ../../modules/security/default.nix
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

  swapDevices = [{ device = "/swapfile"; size = 16384; }];

  nix.settings = { max-jobs = 4; cores = 4; };

  documentation.doc.enable = lib.mkForce false;
  documentation.info.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;

  features.gui.enable = lib.mkForce false;
  features.web.enable = lib.mkForce false;
  features.mail.enable = lib.mkForce false;
  features.hack.enable = lib.mkForce false;
  features.fun.enable = lib.mkForce false;
  features.torrent.enable = lib.mkForce false;
  features.dev.ai.enable = lib.mkForce false;

  boot.lanzaboote.enable = lib.mkForce false;

  environment.systemPackages = [ pkgs.git ];
  users.users.root.hashedPassword = "!";
}
