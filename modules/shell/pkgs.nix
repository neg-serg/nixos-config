{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.bash-completion # programmable completion for bash
    pkgs.carapace # multi-shell multi-command argument completer
    pkgs.dash # POSIX-compliant implementation of /bin/sh (lighter than bash)
    pkgs.nix-bash-completions # bash completion for Nix commands
    pkgs.nix-zsh-completions # zsh completion for Nix commands
    pkgs.oils-for-unix # new Unix shell with bash compatibility
    pkgs.neg.zhist # smarter zsh history: dir/exit-status/duration per command + fzf picker (replaces native history file)
  ];
}
