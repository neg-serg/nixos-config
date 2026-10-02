{
  lib,
  mkBool,
  ...
}:
let
  # One AppArmor state per daemon. Profiles themselves live in
  # modules/security/apparmor.nix; see docs/howto/apparmor.md.
  mkState =
    daemon:
    lib.mkOption {
      type = lib.types.enum [
        "disable"
        "complain"
        "enforce"
      ];
      default = "complain";
      description = "AppArmor state for the ${daemon} profile: disable (not loaded at all), complain (denials are logged but allowed), enforce (denials are blocked). Flip to enforce only after a boot with this profile in complain has been reviewed.";
      example = "enforce";
    };
in
{
  options.features.security = {
    # TPM-backed passwordless sudo: a non-exportable SSH key in the TPM
    # (tpm2-pkcs11, empty PIN) + pam_ssh_agent_auth for `sudo`. Flip on only
    # AFTER enabling fTPM in UEFI/BIOS — otherwise boot stalls on the tpmrm
    # device wait. See modules/security/tpm-sudo.nix and docs/howto/tpm-sudo.md.
    tpmSudo.enable = mkBool "TPM-backed passwordless sudo (tpm2-pkcs11 + pam_ssh_agent_auth)" false;
    # Lock runtime module loading at boot (nixpkgs security.lockKernelModules
    # → kernel.modules_disabled=1 right after systemd-modules-load, i.e. after
    # boot.kernelModules/initrd.kernelModules are in). Everything that must
    # exist once the lock is on has to be pre-loaded or built-in (=y).
    # Turned OFF on 2026-09-29 to test hotplug gear live (USB audio/MIDI,
    # gamepads) — set back to true once the testing is done.
    # `.enable` matters: `lib.neg.enabled "security.lockKernelModules"` reads
    # features.security.lockKernelModules.enable — without the suffix the gate
    # above silently stays false forever (guard: flake/checks.nix feature-flags).
    lockKernelModules.enable = mkBool "Lock kernel module loading after boot (kernel.modules_disabled=1); requires everything needed to be pre-loaded via boot.kernelModules or built-in" false;
    # AppArmor confinement for the network-facing daemons. Generated from each
    # daemon's package closure in modules/security/apparmor.nix; all of them
    # ship in "complain" so the first switch is log-only. The last four are
    # session services: the profile attaches to the binary path, so it confines
    # them too (they are the ones with no unit hardening of their own).
    apparmor = {
      enable = mkBool "AppArmor confinement for network-facing daemons (sshd, unbound, AdGuard Home, ntfy, avahi, sing-box, transmission, aria2)" false;
      sshd = mkState "sshd";
      unbound = mkState "unbound";
      adguardhome = mkState "adguardhome";
      ntfy = mkState "ntfy";
      avahi = mkState "avahi";
      singbox = mkState "sing-box";
      transmission = mkState "transmission";
      aria2 = mkState "aria2";
    };
  };
}
