{
  lib,
  pkgs,
  ...
}:
let
  # Wrap ugrep/ug to load the system-wide /etc/ugrep.conf via env var
  # (--config flag triggers a security check in ugrep 7.8 that rejects
  # root-owned config when running as non-root; the env var bypasses it.)
  ugrepWithConfig = pkgs.ugrep.overrideAttrs (old: {
    # Ultra fast grep with interactive query UI
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/ugrep" --set UGREP_CONFIG_FILE "/etc/ugrep.conf"
      wrapProgram "$out/bin/ug" --set UGREP_CONFIG_FILE "/etc/ugrep.conf"
    '';
  });
  hishtoryPkg = pkgs.hishtory or null; # Your shell history: synced, queryable, and in context
in
{
  environment.shellAliases = {
    sk = "nix run github:neg-serg/two_percent --";
    newsraft = "nix run nixpkgs#newsraft --";
    tealdeer = "nix run nixpkgs#tealdeer --";
  };

  environment.systemPackages = [
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
    pkgs.superfile # fancy terminal file manager with TUI
    pkgs.stow # manage farms of symlinks
    pkgs.zoxide # smarter cd with ranking

    # Utilities
    pkgs.dcfldd # dd with progress/hash
    pkgs.dust # better du
    pkgs.erdtree # modern tree
    pkgs.eza # modern 'ls' replacement
    pkgs.libnotify # notify-send helper used by CLI scripts
    pkgs.moreutils # assorted unix utils (sponge, etc.)
    pkgs.ncdu_1 # interactive du (C version, no zig/LLVM dep)
    pkgs.neg.duf # better df (fork with plain style support)
    pkgs.neg.talktype # push-to-talk voice typing (F9 record, transcribe, paste)
    pkgs.neg.termeverything # Wayland compositor that renders GUI windows in the terminal
    pkgs.pwgen # password generator
  ]
  ++ lib.optional (hishtoryPkg != null) hishtoryPkg; # sync shell history w/ encryption, better than zsh-histdb
}
