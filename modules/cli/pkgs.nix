{pkgs, ...}: let
  # Wrap ugrep/ug to always load the system-wide /etc/ugrep.conf
  ugrepWithConfig = pkgs.ugrep.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
    postInstall =
      (old.postInstall or "")
      + ''
        wrapProgram "$out/bin/ugrep" --add-flags "--config=/etc/ugrep.conf"
        wrapProgram "$out/bin/ug" --add-flags "--config=/etc/ugrep.conf"
      '';
  });
in {
  environment.systemPackages = [
    pkgs.abduco # CLI session detach
    pkgs.ast-grep # AST-aware grep
    pkgs.delta # better diff tool
    pkgs.difftastic # syntax-aware diff
    pkgs.diffutils # classic diff utils
    pkgs.doggo # DNS client for humans
    pkgs.dos2unix # file conversion
    pkgs.du-dust # better du
    pkgs.duf # better df
    pkgs.eza # modern 'ls' replacement
    pkgs.fd # better find
    pkgs.file # detect file type by content
    pkgs.goaccess # realtime log analyzer
    pkgs.grc # generic text colorizer
    pkgs.inotify-tools # shell inotify bindings
    pkgs.kmon # kernel activity monitor
    pkgs.lnav # fancy log viewer
    pkgs.lsof # list open files
    pkgs.moreutils # assorted unix utils (sponge, etc.)
    pkgs.ncdu # interactive du
    pkgs.nnn # CLI file manager
    pkgs.parallel # parallel xargs
    pkgs.procps # /proc tools
    pkgs.progress # show progress for coreutils
    pkgs.psmisc # killall and friends
    pkgs.pueue # queue manager
    pkgs.pv # pipe viewer
    pkgs.readline # readline library
    pkgs.reptyr # move app to another pty
    pkgs.ripgrep # better grep
    pkgs.rlwrap # readline wrapper for everything
    pkgs.rmlint # remove duplicates
    pkgs.stow # manage farms of symlinks
    pkgs.tig # git TUI
    ugrepWithConfig # better grep, rg alternative (wrapped with global config)
  ];
}
