{pkgs, ...}: let
  # Path to the nushell config files in this repo
  nuConfDir = ./nushell-conf;

  # oh-my-posh theme config path
  ompConfig = ../../files/shell/zsh/neg.omp.json;
in {
  programs.nushell = {
    enable = true;

    # Use the custom env.nu directly
    envFile.source = "${nuConfDir}/env.nu";

    # Use the config.nu directly
    configFile.source = "${nuConfDir}/config.nu";

    # Use shellAliases for aliae-style aliases (no IFD, no source needed)
    shellAliases = {
      # Core aliases from aliae config
      cat = "bat -pp";
      l = "eza --icons=auto --hyperlink";
      ll = "eza --icons=auto --hyperlink -l";
      lsd = "eza --icons=auto --hyperlink -alD --sort=created --color=always";
      gs = "git status -sb";
      e = "handlr open";
      tree = "erd";
      gzip = "pigz";
      bzip2 = "pbzip2";
      locate = "plocate";
      ping = "prettyping";
    };

    # oh-my-posh prompt via environment hooks (no source needed)
    extraEnv = ''
      # Set oh-my-posh prompt command
      $env.PROMPT_COMMAND = {||
        ${pkgs.oh-my-posh}/bin/oh-my-posh print primary --config=${ompConfig}
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
