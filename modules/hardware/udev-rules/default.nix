{ config, ... }:
{
  services.udev.extraRules = config.lib.neg.readFile "files/hardware/udev/default.rules";
}
