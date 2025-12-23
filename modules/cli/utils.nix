{
  lib,
  pkgs,
  ...
}: let
  hishtoryPkg = pkgs.hishtory or null;
in {
  environment.systemPackages =
    [
      pkgs.amfora # Gemini/Gopher terminal client for text browsing
      pkgs.dcfldd # dd with progress/hash
      pkgs.dust # better du
      pkgs.erdtree # modern tree
      pkgs.eza # modern 'ls' replacement
      pkgs.gemini-cli # Google Gemini prompt CLI with streaming UI beats curl wrappers
      pkgs.libnotify # notify-send helper used by CLI scripts
      pkgs.moreutils # assorted unix utils (sponge, etc.)
      pkgs.ncdu # interactive du

      pkgs.neg.comma # run commands from nixpkgs by name (\",\") - local overlay helper
      pkgs.neg.duf # better df (fork with plain style support)
      pkgs.neg.pretty_printer # ppinfo CLI + Python module for scripts
      pkgs.neg.two_percent # skim fork optimized as a faster fuzzy finder alternative
      pkgs.newsraft # terminal RSS/Atom feed reader
      pkgs.pwgen # password generator
      pkgs.tealdeer # tldr replacement written in Rust
    ]
    ++ lib.optional (pkgs ? icedtea-web) pkgs.icedtea-web # Java WebStart fallback for legacy consoles
    ++ lib.optional (hishtoryPkg != null) hishtoryPkg; # sync shell history w/ encryption, better than zsh-histdb
}
