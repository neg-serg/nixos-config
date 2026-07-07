{ lib, mkBool, ... }:
with lib;
{
  options.features.apps = {
    obsidian = {
      enable = mkBool "enable Obsidian knowledge base app + vault" false;
    };
    obsidian.autostart.enable = mkBool "autostart Obsidian at GUI login (systemd user service)" false;
    winapps.enable = mkBool "enable WinApps integration (KVM/libvirt Windows VM, RDP bridge)" false;
    throne.enable = mkBool "enable Throne GUI proxy configuration manager" false;
    guiAppsFull.enable = mkBool "enable heavy GUI apps (GIMP, OBS Studio)" true;
  };
}
