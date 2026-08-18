{
  pkgs,
  config,
  lib,
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
  imports = [ ./tpm-sudo.nix ];
  services.pcscd.enable = true; # pkcs support
  # nixpkgs' security.lockKernelModules (enabled below) auto-adds one kernel
  # module per fileSystem entry; our bind mounts use fsType = "none", which
  # would be loaded as a (nonexistent) module at boot ("Failed to find module
  # 'none'"). boot.kernelModules is an attrset-of-bool, so mkForce-ing this
  # attr to false drops it from the final list without touching the mounts.
  boot.kernelModules.none = lib.mkForce false;
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
    lockKernelModules = true;
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
        Defaults timestamp_timeout = 15 # makes sudo ask for password less often
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
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/ryzenadj";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/gpu-oc";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl stop xray.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl start xray.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl stop sing-box-tun.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl start sing-box-tun.service";
              options = [ "NOPASSWD" ];
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
