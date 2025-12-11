{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.features.dev.emacs or {enable = false;};
  emacsPackage = pkgs.emacs29-pgtk;
in {
  config = mkIf (cfg.enable or false) {
    programs.emacs = {
      enable = true;
      package = emacsPackage;
      extraPackages = epkgs:
        with epkgs; [
          # Core infrastructure
          use-package # declarative package configuration
          general # keybinding framework
          evil # vim emulation layer
          evil-collection # evil bindings for many modes
          which-key # display available keybindings

          # Completion framework
          vertico # vertical completion UI
          orderless # flexible matching style
          marginalia # annotations in minibuffer
          consult # search and navigation commands
          corfu # in-buffer completion popup
          cape # completion-at-point extensions

          # UI enhancements
          doom-themes # curated theme collection
          doom-modeline # fancy modeline
          all-the-icons # icon support for dired/modeline
          nerd-icons # nerd font icons
          rainbow-delimiters # colorful parentheses

          # Git integration
          magit # git porcelain
          git-gutter # show git diff in fringe
          git-gutter-fringe # bitmap fringe indicators

          # Org-mode ecosystem
          org # outliner and authoring system
          org-bullets # fancy bullets for org headings
          org-appear # reveal markup on cursor
          toc-org # auto-generate table of contents

          # LSP/IDE features
          eglot # built-in LSP client

          # Language modes
          nix-mode # Nix expression syntax
          rust-mode # Rust syntax and integration
          python-mode # Python editing
          yaml-mode # YAML files
          json-mode # JSON files
          markdown-mode # Markdown editing

          # Tools and utilities
          vterm # terminal emulator
          projectile # project management
          treemacs # file tree sidebar
          treemacs-evil # evil keybindings for treemacs
          undo-tree # visual undo history
          wgrep # writable grep buffers
          ripgrep # fast search integration
        ];
    };

    # Symlink config files to ~/.config/emacs/
    xdg.configFile = {
      "emacs/init.el".source = ./init.el;
      "emacs/early-init.el".source = ./early-init.el;
      "emacs/config.org".source = ./config.org;
      "emacs/icons".source = ./icons;
    };

    # Add emacs daemon service
    services.emacs = {
      enable = true;
      client.enable = true;
      defaultEditor = false; # Keep nvim as default
      startWithUserSession = "graphical";
    };
  };
}
