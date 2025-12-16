{
  pkgs,
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.programs.television.enable {
    home.packages = with pkgs; [
      television
      nix-search-tv
    ];

    # Hardcoded theme (previously from stylix)
    home.file.".config/television/themes/neg.toml".text = ''
      # general
      # background = nil, transparent
      remote_control_mode_bg = '#00000000'
      border_fg = '#585858'
      text_fg = '#c5c8c6'
      dimmed_text_fg = '#81a2be'
      # input
      input_text_fg = '#cc6666'
      result_count_fg = '#cc6666'
      # results
      result_name_fg = '#81a2be'
      result_line_number_fg = '#f0c674'
      result_value_fg = '#e0e0e0'
      selection_fg = '#b5bd68'
      selection_bg = '#373b41'
      match_fg = '#cc6666'
      # preview
      preview_title_fg = '#de935f'
      # modes
      channel_mode_fg = '#c5c8c6'
      remote_control_mode_fg = '#b5bd68'
      send_to_channel_mode_fg = '#81a2be'
    '';

    home.file.".config/television/config.toml".source = ./config.toml;
    home.file.".config/television/cable/nix.toml".source = ./nix.toml;

    programs.zsh.initExtra = builtins.readFile ./zshrc;
  };
}
