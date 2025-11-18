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
    pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
    pkgs.ast-grep # AST-aware grep
    pkgs.delta # better diff tool
    pkgs.difftastic # syntax-aware diff
    pkgs.diffutils # classic diff utils
    pkgs.doggo # DNS client for humans
    pkgs.dos2unix # file conversion
    pkgs.dust # better du
    pkgs.duf # better df
    pkgs.eza # modern 'ls' replacement
    pkgs.fd # better find
    pkgs.file # detect file type by content
    pkgs.asciinema-agg # render asciinema casts to GIF/APNG
    pkgs.gum # TUIs for shell prompts/menus
    pkgs.goaccess # realtime log analyzer
    pkgs.grc # generic text colorizer
    pkgs.inotify-tools # shell inotify bindings
    pkgs.jq # ubiquitous JSON processor for scripts
    pkgs.kmon # kernel activity monitor
    pkgs.libnotify # notify-send helper used by CLI scripts
    pkgs.lnav # fancy log viewer
    pkgs.lsof # list open files
    pkgs.moreutils # assorted unix utils (sponge, etc.)
    pkgs.ncdu # interactive du
    pkgs.nnn # CLI file manager
    pkgs.parallel # parallel xargs
    pkgs.peaclock # animated TUI clock (used in panels)
    pkgs.neg.awrit # render web pages inside Kitty
    pkgs.exiftool # EXIF inspector for screenshot helpers
    pkgs.procps # /proc tools
    pkgs.progress # show progress for coreutils
    pkgs.psmisc # killall and friends
    pkgs.pueue # queue manager
    pkgs.pv # pipe viewer
    pkgs.chafa # terminal graphics renderer
    pkgs.gallery-dl # download image galleries
    pkgs.monolith # single-file webpage archiver
    pkgs.pipe-viewer # terminal YouTube client
    pkgs.prettyping # fancy ping output
    pkgs.whois # domain info lookup
    pkgs.xidel # extract webpage segments
    pkgs.qrencode # QR generator for clipboard helpers
    pkgs.readline # readline library
    pkgs.reptyr # move app to another pty
    pkgs.ripgrep # better grep
    pkgs.rlwrap # readline wrapper for everything
    pkgs.rmlint # remove duplicates
    pkgs.sox # audio swiss-army knife for CLI helpers
    pkgs.stow # manage farms of symlinks
    pkgs.tig # git TUI
    pkgs.translate-shell # translate CLI used inside menus
    pkgs.yt-dlp # video downloader used across scripts
    pkgs.zbar # QR/barcode scanner
    ugrepWithConfig # better grep, rg alternative (wrapped with global config)
  ];
}
