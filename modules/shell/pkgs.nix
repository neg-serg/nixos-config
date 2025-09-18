{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.bash-completion # generic bash completions
    pkgs.carapace # universal autocompletion
    pkgs.dash # faster sh
    pkgs.nix-bash-completions # nix-related bash-completions
    pkgs.nix-zsh-completions # nix-related zsh-completion
    pkgs.nushell # modern shell written in Rust
    pkgs.oils-for-unix # better bash
  ];
}
