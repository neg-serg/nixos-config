{
  lib,
  pkgs,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
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
        configure = {
          customRC = "";
          packages.myVimPackage = {
            start = [
              pkgs.vimPlugins.lazy-nvim
              pkgs.fsread-nvim
              (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
                p.bash              # Bash shell script parser
                p.caddy             # Caddy web server config parser
                p.cmake             # CMake build system parser
                p.diff              # Diff format parser
                p.dockerfile        # Dockerfile parser
                p.gitcommit         # Git commit message parser
                p.gitignore         # .gitignore parser
                p.glsl              # GLSL shader language parser
                p.ini               # INI configuration file parser
                p.just              # Justfile parser
                p.kconfig           # Kconfig parser (Linux kernel config)
                p.lua               # Lua language parser
                p.luadoc            # Lua documentation parser
                p.make              # Makefile parser
                p.markdown          # Markdown parser
                p.markdown_inline   # Markdown inline parser
                p.meson             # Meson build system parser
                p.ninja             # Ninja build system parser
                p.nix               # Nix language parser
                p.python            # Python language parser
                p.query             # Treesitter query language parser
                p.regex             # Regular expression parser
                p.wgsl              # WGSL shader language parser
                p.xml               # XML language parser
                p.yaml              # YAML language parser
              ]))
            ];
          };
        };
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

        # Environment tooling
        pkgs.ripgrep # project-wide search backend
        pkgs.fd # fast file finder used by pickers
        pkgs.tree-sitter # parser generator for treesitter
        pkgs.gcc # Needed for treesitter parsers compilation

        # -- LSPs & Tooling --
        pkgs.bash-language-server # Bash LSP for shell scripts
        pkgs.neovim-remote # nvr helper for external editor integration
        pkgs.nil # Nix LSP (fast)
        pkgs.pylyzer # static type analyzer for Python
        pkgs.pyright # Microsoft Pyright LSP
        pkgs.ruff # Python formatter/linter CLI + LSP
        pkgs.clang-tools # clangd/clang-format for C/C++
        pkgs.lua-language-server # Lua LSP
        pkgs.hyprls # Hyprland config LSP
        pkgs.yaml-language-server # YAML LSP
        pkgs.taplo # TOML LSP/formatter
        pkgs.marksman # Markdown LSP
        pkgs.qt6.qtdeclarative # qmlfmt/qmlcachegen for QML editing
        pkgs.qt6.qttools # qmlscene/lrelease etc. for QML dev
        pkgs.just-lsp # LSP for justfiles
        pkgs.lemminx # XML language server
        pkgs.awk-language-server # AWK LSP
        pkgs.autotools-language-server # Autoconf/Automake LSP
        pkgs.cmake-language-server # CMake LSP
        pkgs.dhall-lsp-server # Dhall LSP
        pkgs.docker-compose-language-service # docker-compose schema validation
        pkgs.dockerfile-language-server # Dockerfile LSP
        pkgs.dot-language-server # Graphviz DOT LSP
        pkgs.asm-lsp # Assembly language server
        pkgs.systemd-language-server # systemd unit LSP
        pkgs.nginx-language-server # nginx.conf language server
        pkgs.zls # Zig language server

        # -- Debuggers (DAP) --
        pkgs.lldb # LLVM debugger (C/C++/Rust)

        # -- Formatters --
        pkgs.stylua # Lua formatter
        pkgs.shfmt # Shell formatter
        pkgs.nixfmt # Nix formatter
        pkgs.cmake-format # CMake formatter
        pkgs.isort # Python import sorter
        pkgs.black # Python formatter
      ];
    }
    (n.mkHomeFiles {
      # Symlink nvim config directory
      ".config/nvim".source = n.linkImpure nvimConf;
    })
  ]
)