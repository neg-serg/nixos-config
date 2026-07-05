{
  lib,
  pkgs,
  config,
  neg,
  ...
}:
let
  n = neg;
  devEnabled = config.features.dev.enable or false;
  nvimConf = ../../files/nvim;
in
lib.mkIf devEnabled (
  lib.mkMerge [
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        withPython3 = true;
        withNodeJs = true;
        withRuby = false;
      };

      environment.sessionVariables.NVIM_APPNAME = "";
      environment.shellAliases = {
        nvim = "NVIM_APPNAME= nvim";
        vim = "NVIM_APPNAME= nvim";
        vi = "NVIM_APPNAME= nvim";
      };

      environment.systemPackages = [
        pkgs.neovim-remote # nvr: control neovim from external tools
        (pkgs.makeDesktopItem {
          name = "neovim";
          desktopName = "Neovim";
          genericName = "Text Editor";
          exec = "env NVIM_APPNAME= nvim %F";
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
            "text/x-moc"
            "text/x-pascal"
            "text/x-tcl"
            "text/x-tex"
            "application/x-shellscript"
            "text/x-c"
            "text/x-c++"
          ];
        })

        # Search tools for fzf-lua and telescope
        pkgs.ripgrep # project-wide search backend
        pkgs.fd # fast file finder
        pkgs.fzf # fuzzy finder binary (for fzf-lua)
        pkgs.marksman # Markdown LSP (mason build fails on NixOS — use nixpkgs instead)
      ];
    }
    (n.mkHomeFiles {
      ".config/nvim".source = n.linkImpure nvimConf;
    })
  ]
)
