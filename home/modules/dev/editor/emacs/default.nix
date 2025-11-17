{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.features.dev;
  featureEnabled = (cfg.enable or false) && (cfg.emacs.enable or false);

  inherit (inputs) emacsOverlay nixQmlSupport;

  newpkgs =
    pkgs.appendOverlays
    (with emacsOverlay.overlays; [
      emacs
      package
      (final: prev: {
        tree-sitter = prev.tree-sitter.override {
          extraGrammars = {
            tree-sitter-astro = {
              version = "master";
              src = pkgs.fetchFromGitHub {
                owner = "virchau13";
                repo = "tree-sitter-astro";
                rev = "0ad33e32ae9726e151d16ca20ba3e507ff65e01f";
                sha256 = "LhehKOhCDPExEgEiOj3TiuFk8/DohzYhy/9GmUSxaIg=";
              };
            };
          };
        };
      })
    ]);

  tree-sitter-parsers = grammars:
    with grammars; [
      tree-sitter-bash
      tree-sitter-c
      tree-sitter-c-sharp
      tree-sitter-cmake
      tree-sitter-cpp
      tree-sitter-css
      tree-sitter-dot
      tree-sitter-elisp
      tree-sitter-glsl
      tree-sitter-haskell
      tree-sitter-html
      tree-sitter-java
      tree-sitter-javascript
      tree-sitter-json
      tree-sitter-json5
      tree-sitter-kotlin
      tree-sitter-latex
      tree-sitter-llvm
      tree-sitter-lua
      tree-sitter-make
      tree-sitter-markdown
      tree-sitter-markdown-inline
      tree-sitter-nickel
      tree-sitter-nix
      tree-sitter-prisma
      tree-sitter-python
      nixQmlSupport.packages.${pkgs.stdenv.system}.tree-sitter-qmljs
      tree-sitter-regex
      tree-sitter-rust
      tree-sitter-scss
      tree-sitter-sql
      tree-sitter-toml
      tree-sitter-tsx
      tree-sitter-typescript
      tree-sitter-astro
      tree-sitter-vim
      tree-sitter-yaml
      tree-sitter-zig
    ];

  custom-emacs = with newpkgs;
    (emacsPackagesFor (emacs30-pgtk.override {withNativeCompilation = true;})).emacsWithPackages (epkgs:
      with epkgs; [
        avy
        better-jumper
        company
        crux
        cmake-font-lock
        direnv
        editorconfig
        evil
        evil-collection
        evil-goggles
        face-explorer
        flycheck
        frames-only-mode
        fussy
        glsl-mode
        groovy-mode
        haskell-ts-mode
        just-mode
        kotlin-mode
        lsp-mode
        lsp-treemacs
        lsp-ui
        lsp-haskell
        lsp-java
        magit
        markdown-mode
        nasm-mode
        nix-mode
        reformatter
        projectile
        nixQmlSupport.packages.${pkgs.stdenv.system}.qml-ts-mode
        astro-ts-mode
        rainbow-mode
        string-inflection
        (treesit-grammars.with-grammars tree-sitter-parsers)
        treemacs
        treemacs-evil
        treemacs-projectile
        treemacs-magit
        undo-tree
        use-package
        vertico
        which-key
        melpaPackages.ws-butler
        zig-ts-mode
      ]);
in {
  config = lib.mkIf featureEnabled {
    home.packages = config.lib.neg.pkgsList [custom-emacs];

    services.emacs = {
      enable = true;
      package = custom-emacs;
    };
  };
}
