{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.bsh;
  featureCfg = config.features.cli.bsh or { enable = false; };
  # Resolve enable without recursion
  shouldEnable = cfg.enable || featureCfg.enable;
in
{
  options.programs.bsh = {
    enable = mkEnableOption "BSH (Better Shell History)";

    package = mkOption {
      type = types.package;
      default = pkgs.neg.bsh;
      defaultText = literalExpression "pkgs.neg.bsh";
      description = "The bsh package to use.";
    };
  };

  config = mkIf shouldEnable {
    # Install bsh package
    environment.systemPackages = [ cfg.package ];

    # Zsh integration
    programs.zsh.interactiveShellInit = ''
      # BSH (Better Shell History) Integration
      export BSH_BINARY="${cfg.package}/bin/bsh"
      export BSH_DAEMON="${cfg.package}/bin/bsh-daemon"

      # Source the bsh integration script
      if [[ -f "${cfg.package}/share/bsh/scripts/bsh_init.zsh" ]]; then
        # Override BSH_REPO_ROOT for Nix installation
        export BSH_REPO_ROOT="${cfg.package}"
        source "${cfg.package}/share/bsh/scripts/bsh_init.zsh"
      fi
    '';
  };
}
