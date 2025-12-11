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
          # Core
          use-package
          general
          evil
          evil-collection
          which-key

          # Completion
          vertico
          orderless
          marginalia
          consult
          corfu
          cape

          # UI
          doom-themes
          doom-modeline
          all-the-icons
          nerd-icons
          rainbow-delimiters

          # Git
          magit
          git-gutter
          git-gutter-fringe

          # Org
          org
          org-bullets
          org-appear
          toc-org

          # LSP
          eglot

          # Languages
          nix-mode
          rust-mode
          python-mode
          yaml-mode
          json-mode
          markdown-mode

          # Tools
          vterm
          projectile
          treemacs
          treemacs-evil
          undo-tree
          wgrep
          ripgrep
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
