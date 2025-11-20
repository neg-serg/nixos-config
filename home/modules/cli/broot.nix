{
  lib,
  config,
  xdg,
  ...
}: let
  brootRoot = config.neg.hmConfigRoot + "/files/shell/broot";
in {
  programs.broot = {
    enable = true;
    settings = {
      content_search_max_file_size = "10MB";
      enable_kitty_keyboard = false;
      imports = [
        "verbs.hjson"
        {
          file = "skins/dark-blue.hjson";
          luma = ["dark" "unknown"];
        }
        {
          file = "skins/white.hjson";
          luma = "light";
        }
      ];
      lines_after_match_in_preview = 1;
      lines_before_match_in_preview = 1;
      modal = false;
      preview_transformers = [];
      show_selection_mark = true;
      verbs = [];
    };
  };

  xdg.configFile = lib.mkIf (builtins.pathExists brootRoot) {
    "broot/conf.hjson".source = brootRoot + "/conf.hjson";
    "broot/conf.toml".source = brootRoot + "/conf.toml";
    "broot/to_stdout.hjson".source = brootRoot + "/to_stdout.hjson";
    "broot/launcher".source = brootRoot + "/launcher";
  };
}
