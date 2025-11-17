{
  lib,
  config,
  pkgs,
  xdg,
  ...
}: let
  cfg = config.features.cli.fastCnf;
in {
  options.features.cli.fastCnf.enable =
    (lib.mkEnableOption "fast zsh command-not-found via nix-index") // {default = true;};

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (xdg.mkXdgText "zsh-nix/20-cnf-nix-index.zsh" ''
      # Fast command_not_found_handler using nix-index (prebuilt DB)
      # Requires an up-to-date nix-index database (handled by HM timer).
      # If multiple packages provide the command, prints all and a hint.
      command_not_found_handler() {
        emulate -L zsh
        setopt localoptions noshwordsplit

        local cmd
        cmd="$1"
        shift || true

        # Ignore empty invocations
        if [[ -z "$cmd" ]]; then
          return 127
        fi

        local locate
        locate="${pkgs.nix-index}/bin/nix-locate"
        if [[ ! -x "$locate" ]]; then
          return 127
        fi

        # Query only executables under /bin for speed and relevance
        local matches
        matches="$($locate --top-level --minimal --at-root --whole-name "/bin/$cmd" 2>/dev/null)"

        if [[ -n "$matches" ]]; then
          local first
          first="''${matches%%$'\n'*}"
          print -P "%F{yellow}nix-index:%f %B$cmd%B is provided by:"
          print -rl -- $matches | sed 's/^/  - /'
          print -P "Use: %B, $cmd%b  or  %Bnix shell nixpkgs#$first -c $cmd%b"
          return 127
        fi

        return 127
      }
    '')
  ]);
}
