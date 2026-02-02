{ pkgs, ... }:
{
  # Android development and emulation setup
  environment.systemPackages = with pkgs; [
    android-studio
    android-tools
  ];

  # Allow non-root users in 'kvm' group to use /dev/kvm
  # (This is usually default but good to be explicit for emulators)
  users.groups.kvm = { };
}
