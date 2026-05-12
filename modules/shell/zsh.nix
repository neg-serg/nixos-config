{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    interactiveShellInit = ''
      # Carapace completions
      export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
      zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
      source <(${pkgs.carapace}/bin/carapace _carapace)
    '';
  };
}
