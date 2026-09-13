{
  services.udev.extraRules = builtins.readFile ../../../files/hardware/udev/default.rules;
}
