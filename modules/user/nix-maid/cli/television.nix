{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  n = neg;
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
        ".config/television/config.toml".text = ''
          [general]
          tick_rate = 50
          enable_mouse_support = false
          shell_integration = true
          enable_confirm_quit = false

          [ui]
          show_preview_on_start = false
          nerd_font_icons = true
          scale = 100
          theme = "custom"

          [previewers]
          file_previewer = { command = "bat", args = ["-n", "--color=always", "--style=plain", "--wrap=character", "--terminal-width=50", "{}"] }
          directory_previewer = { command = "eza", args = ["--tree", "--color=always", "--icons=always", "--group-directories-first", "{}"] }

          [[keybindings]]
          keys = [ { All = "ctrl-a" } ]
          action = "ToggleSelectAll"

          [[keybindings]]
          keys = [ { All = "ctrl-y" } ]
          action = "CopySelectedEntriesToClipboard"

          [[keybindings]]
          keys = [ { All = "ctrl-o" } ]
          action = "ShellIntegrationIgnoreAndExecute"

          [[keybindings]]
          keys = [ { All = "ctrl-v" } ]
          action = "ShellIntegrationAppendAndExecute"

          [[keybindings]]
          keys = [ { All = "ctrl-space" } ]
          action = "ToggleSelection"

          [[keybindings]]
          keys = [ { All = "tab" } ]
          action = "TogglePreview"
          once = true

          [[keybindings]]
          keys = [ { All = "ctrl-t" } ]
          action = "ToggleSendToChannel"

          [[keybindings]]
          keys = [ { All = "ctrl-f" } ]
          action = "ToggleFind"

          [[keybindings]]
          keys = [ { All = "ctrl-e" } ]
          action = "Explore"

          [[keybindings]]
          keys = [ { All = "ctrl-d" } ]
          action = "ToggleDeleteToTrash"

          [[keybindings]]
          keys = [ { All = "esc" } ]
          action = "TogglePassthrough"

          [[keybindings]]
          keys = [ { All = "ctrl-c" } ]
          action = "TogglePassthrough"

          [[keybindings]]
          keys = [ { All = "ctrl-s" } ]
          action = "ToggleSortByLastUsed"

          [[keybindings]]
          keys = [ { All = "ctrl-n" } ]
          action = "ToggleSortByCount"

          [[keybindings]]
          keys = [ { All = "ctrl-r" } ]
          action = "SwitchToRemoteControl"

          [keybindings.key_event_groups]
          [[keybindings.key_event_groups]]
          keys = [ { All = "pageup" }, { All = "ctrl-b" } ]
          action = "ScrollPreviewUp"

          [[keybindings.key_event_groups]]
          keys = [ { All = "pagedown" }, { All = "ctrl-f" } ]
          action = "ScrollPreviewDown"

          [[keybindings.key_event_groups]]
          keys = [ { All = "up" }, { All = "ctrl-p" } ]
          action = "PreviousEntry"

          [[keybindings.key_event_groups]]
          keys = [ { All = "down" }, { All = "ctrl-n" } ]
          action = "NextEntry"

          [shell_integration]
          [[shell_integration.channels]]
          channel = "nix"
          trigger = { command = "tv", args = ["-c", "nix"] }
          [[shell_integration.channels.keybindings]]
          keys = [ { All = "ctrl-t" } ]
          action = "Autocomplete"

          [[shell_integration.channels]]
          channel = "files"
          trigger = { command = "tv", args = ["-c", "files"] }
          [[shell_integration.channels.keybindings]]
          keys = [ { All = "ctrl-t" } ]
          action = "Autocomplete"

          [[shell_integration.channels]]
          channel = "default"
          trigger = { command = "tv", args = [] }
          [[shell_integration.channels.keybindings]]
          keys = [ { All = "ctrl-r" } ]
          action = "ShellHistory"
        '';

        ".config/television/cable/nix.toml".text = ''
          [metadata]
          name = "nix"
          description = "A channel to find packages and options of NixOS"

          [source]
          command = "nix-search-tv print"

          [preview]
          command = "nix-search-tv preview {}"
        '';

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
      })
    ]
  );
}
