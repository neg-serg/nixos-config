{ pkgs, ... }:
{
  # Android development and emulation setup
  programs.adb.enable = true;

  # Ensure KVM is enabled for emulator acceleration
  virtualisation.libvirtd.enable = true;

  environment.systemPackages = with pkgs; [
    android-studio
    # android-tools is included by programs.adb.enable = true
  ];

  # Allow non-root users in 'kvm' group to use /dev/kvm
  # (This is usually default but good to be explicit for emulators)
  users.groups.kvm = { };
}
