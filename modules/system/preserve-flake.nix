{
  config,
  lib,
  inputs,
  specialArgs,
  ...
}: let
  cfg = config.system.preserveFlake;
in {
  options.system.preserveFlake = lib.mkEnableOption "copy the current flake to /etc/current-flake";

  config = lib.mkIf cfg {
    system.activationScripts.preserve-flake = {
      text = ''
        # Use symlink instead of copy for speed
        echo "Linking current flake to /etc/current-flake..."
        ln -sfn ${if lib.hasAttr "filteredSource" specialArgs then specialArgs.filteredSource else inputs.self.outPath} /etc/current-flake
      '';
      deps = [];
    };
  };
}
