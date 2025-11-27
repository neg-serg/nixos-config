{
  pkgs,
  lib,
  config,
  ...
}: let
  mainUser = config.users.main.name or "neg";
  mainGroup = let
    g = config.users.main.group or null;
  in
    if g == null
    then mainUser
    else g;
in {
  imports = [./modules.nix];
  services.pcscd.enable = true; # pkcs support
  # Tell p11-kit to load/proxy opensc-pkcs11.so, providing all available slots
  # (PIN1 for authentication/decryption, PIN2 for signing).
  environment.etc."pkcs11/modules/opensc-pkcs11".text = ''
    module: ${pkgs.opensc}/lib/opensc-pkcs11.so
  '';

  security = {
    apparmor = {
      enable = true;
      killUnconfinedConfinables = false;
      packages = [pkgs.apparmor-utils pkgs.apparmor-profiles];
    };
    pki.useCompatibleBundle = true;
    lockKernelModules = false;
    polkit = {
      enable = true;
      debug = lib.mkDefault false;
    };
    tpm2 = {
      enable = lib.mkDefault true; # enable Trusted Platform Module 2 support
      abrmd.enable = lib.mkDefault false; # enable Trusted Platform 2 userspace resource manager daemon
      # The TCTI is the "Transmission Interface" that is used to communicate with a
      # TPM. this option sets TCTI environment variables to the specified values if enabled
      #  - TPM2TOOLS_TCTI
      #  - TPM2_PKCS11_TCTI
      tctiEnvironment.enable = lib.mkDefault true;
      pkcs11.enable = lib.mkDefault false; # enable TPM2 PKCS#11 tool and shared library in system path
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
        sudo-rs.u2fAuth = false;
        sudo.u2fAuth = false;
        # Enable AppArmor-aware PAM for common services
        login.enableAppArmor = true;
        sshd.enableAppArmor = true;
        sudo.enableAppArmor = true;
        sudo-rs.enableAppArmor = true;
        su.enableAppArmor = true;
        greetd.enableAppArmor = true;
      };

      u2f = {
        enable = false;
        settings.cue = false;
        control = "sufficient";
      };
    };

    sudo-rs = {
      enable = true;
      package = pkgs.sudo-rs;
      extraConfig = ''
        Defaults timestamp_timeout = 300 # makes sudo ask for password less often
      '';
      extraRules = [
        {
          commands = [
            {
              command = "${pkgs.systemd}/bin/systemctl suspend";
              options = ["NOPASSWD"];
            }
            {
              command = "${pkgs.systemd}/bin/reboot";
              options = ["NOPASSWD"];
            }
            {
              command = "${pkgs.systemd}/bin/poweroff";
              options = ["NOPASSWD"];
            }
            {
              command = "${pkgs.util-linux}/bin/dmesg";
              options = ["NOPASSWD"];
            }
            {
              command = "${pkgs.amneziawg-tools}/bin/awg-quick";
              options = ["NOPASSWD"];
            }
          ];
          groups = [mainGroup];
        }
      ];
      execWheelOnly = true;
      wheelNeedsPassword = true;
    };
  };
}
