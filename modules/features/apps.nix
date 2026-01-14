{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.apps = {
    obsidian.autostart.enable = mkBool "autostart Obsidian at GUI login (systemd user service)" false;
    discord.system24Theme.enable = mkBool "enable the System24 Discord/Vencord theme" true;
    winapps.enable = mkBool "enable WinApps integration (KVM/libvirt Windows VM, RDP bridge)" false;
    libreoffice.enable = mkBool "enable LibreOffice (Flatpak)" true;
  };
}
