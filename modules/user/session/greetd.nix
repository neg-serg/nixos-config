{
  pkgs,
  lib,
  ...
}: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${lib.getExe pkgs.tuigreet} --time --cmd Hyprland";
        user = "neg";
      };
    };
  };

  # Unlock GPG keyring on login
  security.pam.services.greetd.enableGnomeKeyring = true;
}
