{
  pkgs,
  config,
  ...
}:
let
  mainUser = config.users.main.name or "neg";
  mainGroup =
    let
      g = config.users.main.group or null;
    in
    if g == null then mainUser else g;
in
{
  imports = [ ];
  services.pcscd.enable = true; # pkcs support
  # Tell p11-kit to load/proxy opensc-pkcs11.so, providing all available slots
  # (PIN1 for authentication/decryption, PIN2 for signing).
  environment.etc."pkcs11/modules/opensc-pkcs11".text = ''
    module: ${pkgs.opensc}/lib/opensc-pkcs11.so # smart card support library
  '';

  security = {
    apparmor = {
      enable = true;
      killUnconfinedConfinables = false;
      packages = [
        pkgs.apparmor-utils # user-space tools for apparmor
        pkgs.apparmor-profiles # standard profiles for various apps
        pkgs.roddhjav-apparmor-rules # community profiles for browsers, etc.
      ];
    };
    pki.useCompatibleBundle = true;
    lockKernelModules = false;
    polkit = {
      enable = true;
    };
    pam = {
      loginLimits = [
        {
          domain = "*";
          item = "nofile";
          type = "soft";
          value = "65536";
        }
        {
          domain = "*";
          item = "nofile";
          type = "hard";
          value = "1048576";
        }
        {
          domain = "@gamemode";
          item = "nice";
          type = "-";
          value = "-10";
        }
        {
          domain = "@audio";
          item = "rtprio";
          type = "-";
          value = "95";
        }
        {
          domain = "@audio";
          item = "memlock";
          type = "-";
          value = "4194304";
        }
        {
          domain = mainUser;
          item = "rtprio";
          type = "-";
          value = "95";
        }
        {
          domain = mainUser;
          item = "memlock";
          type = "-";
          value = "4194304";
        }
        {
          domain = "@realtime";
          item = "rtprio";
          type = "-";
          value = "95";
        }
        {
          domain = "@pipewire";
          item = "rtprio";
          type = "-";
          value = "95";
        }
        {
          domain = "@pipewire";
          item = "nice";
          type = "-";
          value = "-19";
        }
        {
          domain = "@pipewire";
          item = "memlock";
          type = "-";
          value = "4194304";
        }
      ];
      services = {
        hyprlock.u2fAuth = false;
        login.u2fAuth = false;

        sudo.u2fAuth = false;
        # Enable AppArmor-aware PAM for common services
        login.enableAppArmor = true;
        sshd.enableAppArmor = true;
        sudo.enableAppArmor = true;

        su.enableAppArmor = true;
        greetd.enableAppArmor = false;
      };

      u2f = {
        enable = false;
        settings.cue = false;
        control = "sufficient";
      };
    };

    sudo = {
      enable = true;
      package = pkgs.sudo;
      extraConfig = ''
        Defaults timestamp_timeout = 300 # makes sudo ask for password less often
        Defaults passprompt="🔐 "
      '';
      extraRules = [
        {
          commands = [
            {
              command = "/run/current-system/sw/bin/systemctl suspend";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/reboot";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/poweroff";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/dmesg";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/awg-quick";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nixos-rebuild";
              options = [
                "NOPASSWD"
                "SETENV"
              ];
            }
          ];
          groups = [ mainGroup ];
        }
      ];
      execWheelOnly = true;
      wheelNeedsPassword = true;
    };
  };
}
