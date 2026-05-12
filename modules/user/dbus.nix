_: {
  services.dbus = {
    enable = true;
    implementation = "broker";
    apparmor = "enabled";
  };
}
