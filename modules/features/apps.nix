{ lib, mkBool, ... }:
with lib;
{
  options.features.apps = {
    obsidian = {
      enable = mkBool "enable Obsidian knowledge base app + vault" false;
    };
    winapps.enable = mkBool "enable WinApps integration (KVM/libvirt Windows VM, RDP bridge)" false;
    winapps.desktopApps = mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "WinApps to generate .desktop files for (e.g. [ \"excel\" \"word\" \"vscode\" ])";
    };
    throne.enable = mkBool "enable Throne GUI proxy configuration manager" false;
  };
}
