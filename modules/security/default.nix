{
  pkgs,
  config,
  lib,
  ...
}:
let
  mainUser = config.lib.neg.mainUser;
  mainGroup =
    let
      g = config.users.main.group or null;
    in
    if g == null then mainUser else g;

  # Positional constructor for the loginLimits table below (nixpkgs expects
  # these four attribute names).  nixfmt expands a four-name `inherit` here,
  # but every call site stays on one line.
  loginLimit = domain: item: type: value: {
    inherit
      domain
      item
      type
      value
      ;
  };
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
        (loginLimit "*" "nofile" "soft" "65536")
        (loginLimit "*" "nofile" "hard" "1048576")
        (loginLimit "@gamemode" "nice" "-" "-10")
        (loginLimit "@audio" "rtprio" "-" "95")
        (loginLimit "@audio" "memlock" "-" "4194304")
        (loginLimit mainUser "rtprio" "-" "95")
        (loginLimit mainUser "memlock" "-" "4194304")
        (loginLimit "@realtime" "rtprio" "-" "95")
        (loginLimit "@pipewire" "rtprio" "-" "95")
        (loginLimit "@pipewire" "nice" "-" "-19")
        (loginLimit "@pipewire" "memlock" "-" "4194304")
      ];
      services = {
        # hyprlock PAM service removed with hyprlock (temporarily disabled, 2026-08-31)
        login.u2fAuth = false;

        sudo.u2fAuth = false;
        # AppArmor-aware PAM for common services: disabled. Processes are
        # unconfined, so change_hat fails on every sudo/login ("unconfined can
        # not change_hat") and only spams the journal + audit. Re-enable when
        # profiles confining these stacks exist.
        login.enableAppArmor = false;
        sshd.enableAppArmor = false;
        sudo.enableAppArmor = false;
        su.enableAppArmor = false;
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
            # amneziawg is off on this host (the out-of-tree module is
            # incompatible with the boot kernel — hosts/odin/hardware.nix) and
            # nothing in the repo calls awg-quick. Its NOPASSWD entry was
            # passwordless arbitrary root: the config path is taken verbatim
            # (CONFIG_FILE="$1", any *.conf) and the file's PostUp/PostDown
            # hooks are run through `eval` as root. Removed; a real VPN up/down
            # needs the root-owned config under /etc/amnezia/amneziawg and can
            # ask for a password.
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
              command = "/run/current-system/sw/bin/glm-adapter-priv";
              options = [ "NOPASSWD" ];
            }
            # `nh os switch` runs its activation as `sudo env <vars> ...`
            # (nix build --profile and <toplevel>/bin/switch-to-configuration),
            # and a NOPASSWD rule for `env *` used to keep it prompt-free.
            # That rule is passwordless arbitrary root (`sudo -n env sh -c …`)
            # and cannot be narrowed by argument wildcards — a pattern like
            # `env * /run/current-system/sw/bin/nixos-rebuild *` also matches
            # `env sh -c '… nixos-rebuild'`. Removed: nh now asks for a
            # password like any other wheel command (wheelNeedsPassword).
            # The agent rollout stays passwordless through the nixos-rebuild
            # rule above (`sudo -n nixos-rebuild …`).
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
