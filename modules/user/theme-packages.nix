{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  qtEnabled = guiEnabled && (config.features.gui.qt.enable or false);
  system = pkgs.stdenv.hostPlatform.system;
  iosevkaInput =
    if inputs ? "iosevka-neg"
    then inputs."iosevka-neg".packages.${system}
    else null;
  iosevkaFont =
    if iosevkaInput != null && (iosevkaInput ? nerd-font)
    then iosevkaInput.nerd-font
    else pkgs.nerd-fonts.iosevka;
  packages =
    [
      pkgs.adw-gtk3
      pkgs.dconf
      iosevkaFont
      pkgs.kora-icon-theme
      pkgs.flight-gtk-theme
      pkgs.cantarell-fonts
    ]
    ++ lib.optionals qtEnabled [
      pkgs.kdePackages.qtstyleplugin-kvantum
      pkgs.libsForQt5.qtstyleplugin-kvantum
    ];
in {
  config = lib.mkIf guiEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
