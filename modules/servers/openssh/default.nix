##
# Module: servers/openssh
# Purpose: OpenSSH + mosh profile (restrictive SSH settings).
# Key options: cfg = config.servicesProfiles.openssh.enable
# Dependencies: Enables programs.mosh.
{
  lib,
  config,
  ...
}:
let
  cfg = config.servicesProfiles.openssh or { enable = false; };
in
{
  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        UseDns = true;
      };
    };
    programs.mosh.enable = true; # Opens the relevant UDP ports.
  };
}
