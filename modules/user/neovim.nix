{
  lib,
  pkgs,
  config,
  neg,
  inputs,
  ...
}:
let
  devEnabled = config.lib.neg.enabled "dev";

  # Neovim nightly (0.13.0-dev) instead of stable 0.12.6: guh.nvim needs
  # `vim.async` (files/nvim/lua/plugins/integration/guh.lua), which only exists
  # after 0.12.6. The flake input pins the exact neovim master rev; the module
  # expects the *unwrapped* build here and applies its own wrapper for the
  # python3/node providers.
  neovimUnwrapped = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.neovim;
  nvimConf = config.lib.neg.path "files/nvim";
  # Deploy each top-level entry as its own symlink (quickshell pattern) instead
  # of one dir symlink, so the config dir itself stays writable at runtime.
  # lazy-lock.json is excluded: it is linked to the tracked repo file below so
  # `:Lazy sync` updates the committed lockfile directly (lua/01-plugins.lua).
  nvimSrcEntries = builtins.readDir nvimConf;
  nvimSrcNames = builtins.filter (name: name != "lazy-lock.json") (builtins.attrNames nvimSrcEntries);
  nvimHomeFiles = neg.mkDirLinks ".config/nvim" nvimConf nvimSrcNames;

  # texlab: a 63 MiB LSP needed only when a LaTeX buffer attaches, so Neovim
  # resolves it from an on-demand launcher instead of the system image.
  onDemand = config.lib.neg.onDemand pkgs;
in
lib.mkIf devEnabled (
  lib.mkMerge [
    {
      programs.neovim = {
        enable = true;
        package = neovimUnwrapped;
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
        # Search backends for snacks pickers
        pkgs.ripgrep # project-wide search backend (snacks grep)
        pkgs.fd # fast file finder (snacks files picker)

        # LSP servers — via nixpkgs, not Mason (Mason binaries break on NixOS:
        # ELF binaries lack /lib64/ld-linux, npm shebangs lack /usr/bin/env).
        # Language-scoped servers are not installed system-wide; they come from
        # the devshell for that language: marksman/lemminx from the default
        # shell (flake/devshells/base.nix), clangd/CMake from `cpp`,
        # rust-analyzer from `rust`, delve from `tools`, vale from `lint`.
        # What stays below is needed in every session or is fetched on first
        # use, whatever the project.
        (onDemand {
          name = "texlab";
          attr = "texlab";
        }) # LaTeX (VimTeX), built on first use; the toolchain lives in the `latex` devshell
        pkgs.lua-language-server # Lua
        pkgs.bash-language-server # Bash
        pkgs.pyright # Python
        (onDemand {
          name = "typescript-language-server";
          attr = "typescript-language-server";
        }) # TypeScript/JavaScript LSP, built on first use
        (onDemand {
          name = "vscode-json-language-server";
          attr = "vscode-langservers-extracted";
          aliases = [
            "vscode-css-language-server"
            "vscode-eslint-language-server"
            "vscode-html-language-server"
          ];
        }) # CSS + HTML + JSON + ESLint LSP servers, built on first use
        pkgs.taplo # TOML
        pkgs.just-lsp # Justfiles
        pkgs.autotools-language-server # Autotools/Make
        pkgs.dot-language-server # DOT graphs
        pkgs.yaml-language-server # YAML
        pkgs.nil # Nix (fast LSP with built-in nixpkgs docs)
        (onDemand {
          name = "docker-language-server";
          attr = "docker-language-server";
        }) # Dockerfile LSP, built on first use
        # CMake LSP/formatter live in the `cpp` devshell together with CMake.
        pkgs.systemd-lsp # Systemd unit LSP

        # Treesitter: the main branch of nvim-treesitter builds parsers with the
        # CLI (`require('nvim-treesitter').install{...}`); without it no parser
        # is ever installed
        pkgs.tree-sitter # tree-sitter-cli equivalent in nixpkgs (0.26.11)

        # Formatters/linters (for conform.nvim and nvim-lint)
        pkgs.prettierd # Multi-language formatter (JS/TS/CSS/HTML)
        pkgs.ruff # Python formatter + linter
        pkgs.shellcheck # Shell linter
        pkgs.shfmt # Shell formatter
        pkgs.stylua # Lua formatter
        pkgs.selene # Lua linter (blazing fast, Rust)
        pkgs.hadolint # Dockerfile linter
        pkgs.yamllint # YAML linter
        pkgs.black # Python formatter (conform.nvim + just lint)
        pkgs.luajit # Lua syntax checker (just lint)
        # qmlls (QML LSP, configured in files/nvim/.../lspconfig.lua) for the
        # Quickshell scenes under ~/.config/quickshell. The store path is
        # already in the closure through SuperCollider/Vicine/Qt tooling, so
        # this entry costs no bytes; qmlformat arrives with the same package.
        pkgs.qt6.qtdeclarative # qmlls + qmlformat for QML (path already in the closure)

        # DAP debug adapters (nvim-dap) + lazygit (Snacks.lazygit)
        # lldb/lldb-dap live in the `cpp` devshell; Rust work already uses
        # codelldb from the `rust` devshell.
        # delve (Go DAP adapter) is provided by the `tools` devshell.
        ((pkgs.python3.withPackages (ps: [ ps.debugpy ])).overrideAttrs (o: {
          meta = (o.meta or { }) // {
            priority = 1;
          }; # wins PATH over plain python3 so `python3 -m debugpy.adapter` works
        })) # Python DAP adapter (nvim-dap)
        (onDemand {
          name = "lazygit";
          attr = "lazygit";
        }) # Git TUI for Snacks.lazygit bindings, built on first use
      ];
    }
    (neg.mkHomeFiles (
      nvimHomeFiles
      // {
        ".config/vale/.vale.ini".source = config.lib.neg.path "files/vale/.vale.ini"; # Vale prose linter config
        ".local/share/vale/styles".source = config.lib.neg.path "files/vale/styles"; # Google prose style rules (styles/Google/)
      }
    ))
    {
      # Remove old nvim config symlinks before nix-maid activation deploys the
      # per-entry symlink tree (the whole-dir symlink becomes a real dir).
      systemd.user.services.nvim-cleanup-symlink = {
        description = "Remove old nvim config symlinks before nix-maid activation";
        before = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "nvim-cleanup-symlink" ''
            nvim_dir="$HOME/.config/nvim"
            if [ -L "$nvim_dir" ]; then
              rm -f "$nvim_dir" 2>/dev/null || true
            elif [ -d "$nvim_dir" ]; then
              find "$nvim_dir" -maxdepth 1 -type l -delete 2>/dev/null || true
            fi
            rm -rf "$HOME/.local/state/nix-maid/static/.config/nvim" 2>/dev/null || true
          '';
        };
      };
      # lazy-lock.json must stay writable at runtime: link it to the tracked
      # repo file so `:Lazy sync` writes the committed lockfile in place.
      systemd.user.services.nvim-lockfile-link = {
        description = "Link writable lazy-lock.json into nvim config";
        after = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "nvim-lockfile-link" ''
            lock="$HOME/.config/nvim/lazy-lock.json"
            target="/etc/nixos/files/nvim/lazy-lock.json" # repo path = config.lib.neg.path "files/nvim/lazy-lock.json"
            if [ -L "$lock" ] && [ "$(readlink "$lock")" = "$target" ]; then
              exit 0
            fi
            rm -f "$lock" 2>/dev/null || true
            ln -s "$target" "$lock"
          '';
        };
      };
    }
  ]
)
