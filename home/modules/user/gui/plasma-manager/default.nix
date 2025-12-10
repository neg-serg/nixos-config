{inputs, ...}: let
  inherit (inputs) plasma-manager;
in {
  imports = [
    plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;
    # Basic configuration to verify it works.
    # User can expand this later.
    workspace = {
      clickItemTo = "select";
      lookAndFeel = "org.kde.breezedark.desktop";
    };
  };
}
