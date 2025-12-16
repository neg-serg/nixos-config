{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.cli.television;
  filesRoot = ../../../files;
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [
      pkgs.television
      pkgs.nix-search-tv
    ];

    users.users.neg.maid.file.home = {
      ".config/television/config.toml".source = "${filesRoot}/television/config.toml";
      ".config/television/cable/nix.toml".source = "${filesRoot}/television/nix.toml";
      ".config/television/themes/custom.toml".text = ''
        # general
        remote_control_mode_bg = '#00000000'
        border_fg = '#6c7e96'
        text_fg = '#8d9eb2'
        dimmed_text_fg = '#0a3749'
        # input
        input_text_fg = '#8a2f58'
        result_count_fg = '#8a2f58'
        # results
        result_name_fg = '#0a3749'
        result_line_number_fg = '#005faf'
        result_value_fg = '#00ff00'
        selection_fg = '#005200'
        selection_bg = '#0f2329'
        match_fg = '#8a2f58'
        # preview
        preview_title_fg = '#914e89'
        # modes
        channel_mode_fg = '#ff0000'
        remote_control_mode_fg = '#005200'
        send_to_channel_mode_fg = '#0a3749'
      '';
    };

    # Inject Zsh widgets system-wide (interactive shells only)
    programs.zsh.interactiveShellInit = ''
      _tv_smart_autocomplete() {
          emulate -L zsh
          zle -I
          # prefix (lhs of cursor)
          local current_prompt
          current_prompt=$LBUFFER
          local output
          output=$(tv --autocomplete-prompt "$current_prompt" $* | tr '\n' ' ')
          if [[ -n $output ]]; then
              # suffix (rhs of cursor)
              local rhs=$RBUFFER
              # add a space if the prompt does not end with one
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
