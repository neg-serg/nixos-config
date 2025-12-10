{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.system.preserveFlake;
in {
  options.system.preserveFlake = lib.mkEnableOption "copy the current flake to /etc/current-flake";

  config = lib.mkIf cfg {
    system.activationScripts.preserve-flake = {
      text = ''
        if [ -d ${inputs.self.outPath} ]; then
          echo "Copying current flake to /etc/current-flake..."
          rm -rf /etc/current-flake
          cp -r ${inputs.self.outPath} /etc/current-flake
          chmod -R u+w /etc/current-flake
        fi
      '';
      deps = [];
    };
  };
}
