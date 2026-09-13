{
  neg,
  lib,
  config,
  ...
}:
{
  imports = neg.importDir { dir = ./.; };

  # Enable upstream QMK module to ship udev rules and create 'plugdev'.
  hardware.keyboard.qmk.enable = true;

  # Add the primary user to 'plugdev' when QMK support is enabled.
  users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "plugdev" ];
  services.udev.extraRules = builtins.readFile (config.lib.neg.path "files/hardware/udev/qmk.rules");
}
