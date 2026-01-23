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
    enable = mkEnableOption "BSH (Better Shell History) - Git-aware predictive terminal history";

    package = mkOption {
      type = types.package;
      default = pkgs.neg.bsh;
      defaultText = literalExpression "pkgs.neg.bsh";
      description = ''
        The bsh package to use.

        BSH provides live predictive suggestions based on:
        - Current working directory
        - Active Git branch
        - Historical command success rates

        Key bindings (customized for NixOS):
        - Alt+1-5: Execute suggested command
        - Alt+Shift+1-5: Insert suggested command
        - Alt+arrows (or Alt+f/Alt+b): Cycle search context
        - Alt+X: Toggle success filter (hide failed commands)
      '';
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
