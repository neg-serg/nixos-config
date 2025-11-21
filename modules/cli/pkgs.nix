{
  lib,
  pkgs,
  ...
}: let
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
  hishtoryPkg = pkgs.hishtory or null;
in {
  environment.systemPackages =
    [
      pkgs.abduco # CLI session detach
      pkgs.amfora # Gemini/Gopher terminal client for text browsing
      pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
      pkgs.asciinema-agg # render asciinema casts to GIF/APNG
      pkgs.ast-grep # AST-aware grep
      pkgs.babashka # native Clojure scripting runtime
      pkgs.below # BPF-based system history
      pkgs.blesh # bluetooth shell helpers
      pkgs.bpftrace # high-level eBPF tracer
      pkgs.chafa # terminal graphics renderer
      pkgs.choose # yet another cut/awk alternative
      pkgs.convmv # convert filename encodings
      pkgs.cpufetch # CPU info fetch
      pkgs.fastfetch # modern ASCII system summary
      pkgs.czkawka # find duplicate/similar files
      pkgs.dcfldd # dd with progress/hash
      pkgs.delta # better diff tool
      pkgs.diff-so-fancy # human-friendly git diff pager
      pkgs.difftastic # syntax-aware diff
      pkgs.diffutils # classic diff utils
      pkgs.doggo # DNS client for humans
      pkgs.dos2unix # file conversion
      pkgs.dust # better du
      pkgs.duf # better df
      pkgs.entr # run commands on file change
      pkgs.erdtree # modern tree
      pkgs.enca # detect + reencode text
      pkgs.eza # modern 'ls' replacement
      pkgs.expect # automate interactive TTY programs
      pkgs.exiftool # EXIF inspector for screenshot helpers
      pkgs.fd # better find
      pkgs.file # detect file type by content
      pkgs.fish # alternative shell
      pkgs.nushell # structured shell for scripts and exploration
      pkgs.gallery-dl # download image galleries
      pkgs.goaccess # realtime log analyzer
      pkgs.grex # generate regexes from examples
      pkgs.grc # generic text colorizer
      pkgs.gum # TUIs for shell prompts/menus
      pkgs.inotify-tools # shell inotify bindings
      pkgs.jq # ubiquitous JSON processor for scripts
      pkgs.kmon # kernel activity monitor
      pkgs.kubectl # Kubernetes CLI
      pkgs.kubectx # fast switch Kubernetes contexts
      pkgs.kubernetes-helm # Helm package manager
      pkgs.libnotify # notify-send helper used by CLI scripts
      pkgs.lnav # fancy log viewer
      pkgs.lsof # list open files
      pkgs.massren # massive rename utility
      pkgs.mergiraf # AST-aware git merge driver
      pkgs.miller # awk/cut/join alternative for CSV/TSV/JSON
      pkgs.monolith # single-file webpage archiver
      pkgs.moreutils # assorted unix utils (sponge, etc.)
      pkgs.ncdu # interactive du
      pkgs.neg.awrit # render web pages inside Kitty
      pkgs.neg.comma # run commands from nixpkgs by name (\",\") - local overlay helper
      pkgs.neg.pretty_printer # ppinfo CLI + Python module for scripts
      pkgs.newsraft # terminal RSS/Atom feed reader
      pkgs.nnn # CLI file manager
      pkgs.onefetch # pretty git repo summaries (used in fetch scripts)
      pkgs.ouch # archive extractor/creator
      pkgs.parallel # parallel xargs
      pkgs.borgbackup # deduplicating backup utility
      pkgs.par # paragraph reformatter
      pkgs.patool # universal archive unpacker (python)
      pkgs.pbzip2 # parallel bzip2 backend
      pkgs.peaclock # animated TUI clock (used in panels)
      pkgs.pigz # parallel gzip backend
      pkgs.pipe-viewer # terminal YouTube client
      pkgs.powershell # Microsoft pwsh shell
      pkgs.prettyping # fancy ping output
      pkgs.procps # /proc tools
      pkgs.progress # show progress for coreutils
      pkgs.psmisc # killall and friends
      pkgs.pueue # queue manager
      pkgs.pv # pipe viewer
      pkgs.pwgen # password generator
      pkgs.qrencode # QR generator for clipboard helpers
      pkgs.ramfetch # RAM info fetch
      pkgs.ranger # curses file manager needed by termfilechooser
      pkgs.readline # readline library
      pkgs.reptyr # move app to another pty
      pkgs.restic # deduplicating backup CLI
      pkgs.rhash # hash sums calculator
      pkgs.ripgrep # better grep
      pkgs.rlwrap # readline wrapper for everything
      pkgs.rmlint # remove duplicates
      pkgs.sad # simpler sed alternative
      pkgs.scaleway-cli # Scaleway cloud CLI
      pkgs.sd # intuitive sed alternative
      pkgs.speedtest-cli # internet speed test
      pkgs.sox # audio swiss-army knife for CLI helpers
      pkgs.stow # manage farms of symlinks
      pkgs.taplo # TOML toolkit (fmt/lsp/lint)
      pkgs.tealdeer # tldr replacement written in Rust
      pkgs.tig # git TUI
      pkgs.translate-shell # translate CLI used inside menus
      pkgs.urlscan # extract URLs from text blobs
      pkgs.urlwatch # watch pages for changes
      pkgs.viddy # modern watch with history
      pkgs.whois # domain info lookup
      pkgs.xidel # extract webpage segments
      pkgs.yt-dlp # video downloader used across scripts
      pkgs.zbar # QR/barcode scanner
      pkgs.zfxtop # Cloudflare/ZFX top-like monitor
      pkgs.zoxide # smarter cd with ranking
      ugrepWithConfig # better grep, rg alternative (wrapped with global config)
    ]
    ++ lib.optional (pkgs ? icedtea-web) pkgs.icedtea-web # Java WebStart fallback for legacy consoles
    ++ lib.optional (hishtoryPkg != null) hishtoryPkg; # sync shell history w/ encryption, better than zsh-histdb
}
