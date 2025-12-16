{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.cli.television;
  filesRoot = ../../../home/files;
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [
      pkgs.television
      pkgs.nix-search-tv
    ];

    users.users.neg.maid.file.home = {
      ".config/television/config.toml".source = "${filesRoot}/television/config.toml";
      ".config/television/cable/nix.toml".source = "${filesRoot}/television/nix.toml";

      ".config/television/themes/stylix.toml".text = let
        sf = config.home-manager.users.neg.lib.stylix.colors;
      in ''
        # general
        remote_control_mode_bg = '#00000000'
        border_fg = '#${sf.base04}'
        text_fg = '#${sf.base05}'
        dimmed_text_fg = '#${sf.base0D}'
        # input
        input_text_fg = '#${sf.base08}'
        result_count_fg = '#${sf.base08}'
        # results
        result_name_fg = '#${sf.base0D}'
        result_line_number_fg = '#${sf.base0A}'
        result_value_fg = '#${sf.base07}'
        selection_fg = '#${sf.base0B}'
        selection_bg = '#${sf.base02}'
        match_fg = '#${sf.base08}'
        # preview
        preview_title_fg = '#${sf.base09}'
        # modes
        channel_mode_fg = '#${sf.base06}'
        remote_control_mode_fg = '#${sf.base0B}'
        send_to_channel_mode_fg = '#${sf.base0D}'
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
