{
  lib,
  pkgs,
  config,
  neg,
  inputs,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  devEnabled = config.features.dev.enable or false;
in
lib.mkIf devEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.neovim-remote # nvr: control neovim from external tools
        (pkgs.makeDesktopItem {
          name = "neovim";
          desktopName = "Neovim";
          genericName = "Text Editor";
          exec = "nvim %F";
          icon = "nvim";
          terminal = true;
          categories = [
            "Utility"
            "TextEditor"
          ];
          mimeTypes = [
            "text/english"
            "text/plain"
            "text/x-makefile"
            "text/x-c++hdr"
            "text/x-c++src"
            "text/x-chdr"
            "text/x-csrc"
            "text/x-java"
            "text/x-moc"
            "text/x-pascal"
            "text/x-tcl"
            "text/x-tex"
            "application/x-shellscript"
            "text/x-c"
            "text/x-c++"
          ];
        })
      ];
      programs.nvf = {
        enable = true;
        defaultEditor = true;
        settings = lib.mkForce (inputs.nvf-config.lib.mkConfig { inherit pkgs; });
      };
      environment.sessionVariables.NVIM_APPNAME = "nvf";
    }

  ]
)
