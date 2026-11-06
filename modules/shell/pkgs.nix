{
  config,
  pkgs,
  ...
}:
let
  # carapace is sourced on every zsh start; the launcher adds one `test -e` to
  # that path and keeps its 102 MiB out of the system closure. The first call
  # after a GC builds the package and GC-roots it under ~/.local/state/nix-apps.
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  environment.systemPackages = [
    pkgs.bash-completion # programmable completion for bash
    (onDemand {
      name = "carapace";
      attr = "carapace";
    }) # multi-shell multi-command argument completer, built on first use
    pkgs.dash # POSIX-compliant implementation of /bin/sh (lighter than bash)
    pkgs.nix-bash-completions # bash completion for Nix commands
    pkgs.nix-zsh-completions # zsh completion for Nix commands
    pkgs.oils-for-unix # new Unix shell with bash compatibility
    pkgs.neg.iris # IRIS — shell auto-completion that works like code editor's IntelliSense (fig-style suggestions)
    pkgs.neg.flow # flow — terminal dashboard for real-time network throughput
  ];
}
