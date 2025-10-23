{ lib, config, ... }:
{
  # Kernel uinput for ydotool/others; grant main user access via the 'uinput' group.
  hardware.uinput.enable = true;
  users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "uinput" "input" ];
}

