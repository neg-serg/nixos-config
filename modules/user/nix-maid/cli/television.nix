{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.cli.television;
  filesRoot = ../../../../files;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.television # Blazingly fast TUI fuzzy finder
          pkgs.nix-search-tv # Search packages on search.nixos.org from your terminal
        ];

        # Inject Zsh widgets system-wide (interactive shells only)
        programs.zsh.interactiveShellInit = ''
          _tv_smart_autocomplete() {
              emulate -L zsh
              zle -I
              local current_prompt
              current_prompt=$LBUFFER
              local output
              output=$(tv --autocomplete-prompt "$current_prompt" $* | tr '\n' ' ')
              if [[ -n $output ]]; then
                  local rhs=$RBUFFER
                  [[ "''${current_prompt}" != *" " ]] && current_prompt="''${current_prompt} "
                  LBUFFER=$current_prompt$output
                  CURSOR=''${#LBUFFER}
                  RBUFFER=$rhs
                  zle reset-prompt
              fi
          }

          _tv_shell_history() {
              emulate -L zsh
              zle -I
              local current_prompt
              current_prompt=$LBUFFER
              local output
              output=$(history -n -1 0 | tv --input "$current_prompt" $*)
              if [[ -n $output ]]; then
                  zle reset-prompt
                  RBUFFER=""
                  LBUFFER=$output
              fi
          }

          zle -N tv-smart-autocomplete _tv_smart_autocomplete
          zle -N tv-shell-history _tv_shell_history
        '';
      }
      (n.mkHomeFiles {
        ".config/television/config.toml".source = "${filesRoot}/television/config.toml";
        ".config/television/cable/nix.toml".source = "${filesRoot}/television/nix.toml";
        ".config/television/themes/custom.toml".source = n.linkImpure ../../../../files/television/custom.toml;
      })
    ]
  );
}
