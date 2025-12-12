{
  lib,
  pkgs,
  ...
}: let
  nuConfDir = ./nushell-conf;
  ompConfig = ../../files/shell/zsh/neg.omp.json;

  shellAliases = import ../../../lib/shell-aliases.nix {
    inherit lib pkgs;
    isNushell = true;
  };
in {
  programs.nushell = {
    enable = true;

    # Use the custom env.nu directly
    envFile.source = "${nuConfDir}/env.nu";

    # Use the config.nu directly
    configFile.source = "${nuConfDir}/config.nu";
    inherit shellAliases;

    extraEnv = ''
      $env.PROMPT_COMMAND = {||
        ${pkgs.oh-my-posh}/bin/oh-my-posh print primary --shell nu --config=${ompConfig}
      }
      $env.PROMPT_COMMAND_RIGHT = ""
    '';
  };

  # Link additional nushell config files to XDG config
  xdg.configFile = {
    "nushell/aliases.nu".source = "${nuConfDir}/aliases.nu";
    "nushell/git.nu".source = "${nuConfDir}/git.nu";
    "nushell/broot.nu".source = "${nuConfDir}/broot.nu";
    "nushell/git-completion.nu".source = "${nuConfDir}/git-completion.nu";
  };

  home.packages = [
    pkgs.carapace # completions for nushell
  ];
}
