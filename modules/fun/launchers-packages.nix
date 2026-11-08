##
# Module: fun/launchers-packages
# Purpose: Ship Proton/Wine helper utilities system-wide for game launchers.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = (config.lib.neg.enabled "fun") && (config.lib.neg.enabled "gui");
  onDemand = config.lib.neg.onDemand pkgs;
  # Vulkan post-processing layer, native only. The 32-bit layer that nixpkgs
  # symlinks into the 64-bit build exists only for 32-bit games, which are not
  # used here (see the Steam override in modules/user/games/launchers.nix); the
  # symlink is what drags pkgsi686Linux (i686 glibc, gcc-lib, libx11) into the
  # closure. vkbasalt-cli rewrites its own copy of the layer path, so it gets
  # the same derivation instead of the stock one.
  vkbasalt = pkgs.vkbasalt.overrideAttrs (old: {
    postInstall = ''
      install -Dm 644 ${old.src}/config/vkBasalt.conf $out/share/vkBasalt/vkBasalt.conf
    '';
  });
  packages = [
    (onDemand {
      name = "protontricks";
      attr = "protontricks";
      aliases = [ "protontricks-launch" ];
    }) # Winetricks wrapper for Proton, built on first use
    pkgs.protonup-ng # install/update Proton-GE builds
    vkbasalt # Vulkan post-processing layer (native only)
    (pkgs.vkbasalt-cli.override { inherit vkbasalt; }) # CLI for vkBasalt configuration
  ];
  # The package's own desktop entries live inside the on-demand root, which is
  # not on XDG_DATA_DIRS; the menu entries are recreated here instead. The
  # `wine` icon comes from the icon theme, so the launcher still shows it.
  desktopItems = [
    (pkgs.makeDesktopItem {
      name = "protontricks";
      desktopName = "Protontricks";
      comment = "A simple wrapper that does winetricks things for Proton enabled games";
      exec = "protontricks --no-term --gui";
      icon = "wine";
      categories = [ "Utility" ];
    })
    (pkgs.makeDesktopItem {
      name = "protontricks-launch";
      desktopName = "Protontricks Launcher";
      comment = "Run a Windows executable inside a Proton game's Wine prefix";
      exec = "protontricks-launch --no-term %f";
      icon = "wine";
      categories = [ "Utility" ];
    })
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter (packages ++ desktopItems);
  };
}
