{
  lib,
  pkgs,
  ...
}:
let
  # Wrap ugrep/ug to always load the system-wide /etc/ugrep.conf
  ugrepWithConfig = pkgs.ugrep.overrideAttrs (old: {
    # Ultra fast grep with interactive query UI
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/ugrep" --add-flags "--config=/etc/ugrep.conf"
      wrapProgram "$out/bin/ug" --add-flags "--config=/etc/ugrep.conf"
    '';
  });
  hishtoryPkg = pkgs.hishtory or null; # Your shell history: synced, queryable, and in context
in
{
  environment.systemPackages = [
    # Search tools
    pkgs.ripgrep # better grep
    ugrepWithConfig # better grep, rg alternative (wrapped with global config)

    # Diff tools
    pkgs.delta # better diff tool
    pkgs.diff-so-fancy # human-friendly git diff pager
    pkgs.diffutils # classic diff utils

    # File management
    pkgs.convmv # convert filename encodings
    pkgs.dos2unix # file conversion
    pkgs.fd # better find
    pkgs.file # detect file type by content
    pkgs.massren # massive rename utility
    pkgs.nnn # CLI file manager
    pkgs.stow # manage farms of symlinks
    pkgs.zoxide # smarter cd with ranking

    # TUI tools
    pkgs.peaclock # animated TUI clock (used in panels)

    # Utilities
    pkgs.dcfldd # dd with progress/hash
    pkgs.dust # better du
    pkgs.erdtree # modern tree
    pkgs.eza # modern 'ls' replacement
    pkgs.gemini-cli # Google Gemini prompt CLI with streaming UI beats curl wrappers
    pkgs.libnotify # notify-send helper used by CLI scripts
    pkgs.moreutils # assorted unix utils (sponge, etc.)
    pkgs.ncdu # interactive du
    pkgs.neg.duf # better df (fork with plain style support)
    pkgs.neg.two_percent # skim fork optimized as a faster fuzzy finder alternative
    pkgs.newsraft # terminal RSS/Atom feed reader
    pkgs.pwgen # password generator
    pkgs.tealdeer # tldr replacement written in Rust
  ]

  ++ lib.optional (hishtoryPkg != null) hishtoryPkg; # sync shell history w/ encryption, better than zsh-histdb
}
