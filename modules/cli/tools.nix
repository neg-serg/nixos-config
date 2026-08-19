{
  lib,
  pkgs,
  ...
}:
let
  # Wrap ugrep/ug to load the system-wide /etc/ugrep.conf.
  # ugrep 7.5 ignores the UGREP_CONFIG_FILE env var entirely (config is only
  # read via --config or the default .ugrep), so pass --config explicitly.
  # NOTE: when nixpkgs bumps ugrep to >= 7.8, --config is rejected for
  # root-owned files when running as non-root — switch back to
  # wrapProgram ... --set UGREP_CONFIG_FILE /etc/ugrep.conf then.
  ugrepWithConfig = pkgs.ugrep.overrideAttrs (old: {
    # Ultra fast grep with interactive query UI
    postInstall = (old.postInstall or "") + ''
      for exe in ugrep ug; do
        real="$out/bin/.$exe-wrapped"
        if [ ! -e "$real" ]; then
          mv "$out/bin/$exe" "$real"
        fi
        cat > "$out/bin/$exe" <<EOF
      #!${pkgs.stdenv.shell}
      exec -a "\$0" "$real" --config=/etc/ugrep.conf "\$@"
      EOF
        chmod +x "$out/bin/$exe"
      done
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
    pkgs.procs # modern 'ps' replacement
    pkgs.pwgen # password generator
    pkgs.sd # intuitive find & replace CLI (sed replacement)
  ]
  ++ lib.optional (hishtoryPkg != null) hishtoryPkg; # sync shell history w/ encryption, better than zsh-histdb
}
