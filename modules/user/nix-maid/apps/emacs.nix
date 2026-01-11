{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.dev.emacs;
  emacsPackage = pkgs.emacs29-pgtk;
  emacsWithPackages = emacsPackage.pkgs.withPackages (
    epkgs: with epkgs; [
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
    ]
  );

  filesRoot = ../../../../files;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ emacsWithPackages ]; # Emacs with a pre-configured set of packages

        systemd.user.services.emacs = {
          description = "Emacs text editor";
          serviceConfig = {
            Type = "notify";
            ExecStart = "${lib.getExe' emacsWithPackages "emacs"} --fg-daemon";
            ExecStop = "${lib.getExe' emacsWithPackages "emacsclient"} --eval '(kill-emacs)'";
            Restart = "on-failure";
          };
          wantedBy = [ "default.target" ];
        };
      }
      (n.mkHomeFiles {
        ".config/emacs/init.el".source = "${filesRoot}/emacs/init.el";
        ".config/emacs/early-init.el".source = "${filesRoot}/emacs/early-init.el";
        ".config/emacs/config.org".source = "${filesRoot}/emacs/config.org";
        ".config/emacs/icons".source = "${filesRoot}/emacs/icons";
      })
    ]
  );
}
