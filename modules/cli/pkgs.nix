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
      # -- Archive / Compression --
      pkgs.ouch # archive extractor/creator
      pkgs.patool # universal archive unpacker (python)
      pkgs.pbzip2 # parallel bzip2 backend
      pkgs.pigz # parallel gzip backend

      # -- Backup --
      pkgs.borgbackup # deduplicating backup utility
      pkgs.restic # deduplicating backup CLI

      # -- Cloud / Sync --
      pkgs.kubectl # Kubernetes CLI
      pkgs.kubectx # fast switch Kubernetes contexts
      pkgs.kubernetes-helm # Helm package manager
      pkgs.nextcloud-client # Nextcloud CLI sync client (nextcloudcmd)
      pkgs.scaleway-cli # Scaleway cloud CLI
      pkgs."yandex-cloud" # Yandex Cloud CLI
      pkgs."yandex-disk" # Yandex Disk sync client and daemon

      # -- Diff / Compare --
      pkgs.delta # better diff tool
      pkgs.diff-so-fancy # human-friendly git diff pager
      pkgs.difftastic # syntax-aware diff
      pkgs.diffutils # classic diff utils

      # -- Download --
      pkgs.aria2 # segmented downloader (used by clip/yt-dlp wrappers)
      pkgs.gallery-dl # download image galleries
      pkgs.monolith # single-file webpage archiver
      pkgs.yt-dlp # video downloader used across scripts

      # -- Duplicate Finder --
      pkgs.czkawka # find duplicate/similar files
      pkgs.fclones # fast content-based duplicate finder
      pkgs.jdupes # deduplicate identical files via hardlinks
      pkgs.rmlint # remove duplicates

      # -- File Management --
      pkgs.convmv # convert filename encodings
      pkgs.dos2unix # file conversion
      pkgs.fd # better find
      pkgs.file # detect file type by content
      pkgs.massren # massive rename utility
      pkgs.nnn # CLI file manager
      pkgs.ranger # curses file manager needed by termfilechooser
      pkgs.stow # manage farms of symlinks
      pkgs.zoxide # smarter cd with ranking

      # -- Git --
      pkgs.mergiraf # AST-aware git merge driver
      pkgs.onefetch # pretty git repo summaries (used in fetch scripts)
      pkgs.tig # git TUI

      # -- Grep / Search --
      pkgs.ast-grep # AST-aware grep
      pkgs.ripgrep # better grep
      ugrepWithConfig # better grep, rg alternative (wrapped with global config)

      # -- JSON / Data Processing --
      pkgs.jq # ubiquitous JSON processor for scripts
      pkgs.miller # awk/cut/join alternative for CSV/TSV/JSON
      pkgs.taplo # TOML toolkit (fmt/lsp/lint)
      pkgs.xidel # extract webpage segments

      # -- Logs / Monitoring --
      pkgs.below # BPF-based system history
      pkgs.bpftrace # high-level eBPF tracer
      pkgs.goaccess # realtime log analyzer
      pkgs.kmon # kernel activity monitor
      pkgs.lnav # fancy log viewer
      pkgs.viddy # modern watch with history
      pkgs.zfxtop # Cloudflare/ZFX top-like monitor

      # -- Media / Graphics --
      pkgs.asciinema-agg # render asciinema casts to GIF/APNG
      pkgs.chafa # terminal graphics renderer
      pkgs.exiftool # EXIF inspector for screenshot helpers
      pkgs.pipe-viewer # terminal YouTube client
      pkgs.sox # audio swiss-army knife for CLI helpers
      pkgs.zbar # QR/barcode scanner

      # -- Networking --
      pkgs.doggo # DNS client for humans
      pkgs.prettyping # fancy ping output
      pkgs.speedtest-cli # internet speed test
      pkgs.urlscan # extract URLs from text blobs
      pkgs.urlwatch # watch pages for changes
      pkgs.whois # domain info lookup

      # -- Process / System --
      pkgs.entr # run commands on file change
      pkgs.inotify-tools # shell inotify bindings
      pkgs.lsof # list open files
      pkgs.parallel # parallel xargs
      pkgs.procps # /proc tools
      pkgs.progress # show progress for coreutils
      pkgs.psmisc # killall and friends
      pkgs.pueue # queue manager
      pkgs.pv # pipe viewer
      pkgs.reptyr # move app to another pty

      # -- QR / Encoding --
      pkgs.qrencode # QR generator for clipboard helpers
      pkgs.rhash # hash sums calculator

      # -- Remote / Session --
      pkgs.abduco # CLI session detach
      pkgs.xxh # SSH wrapper for jumping into remote shells

      # -- Shell / REPL --
      pkgs.babashka # native Clojure scripting runtime
      pkgs.blesh # bluetooth shell helpers
      pkgs.expect # automate interactive TTY programs
      pkgs.fish # alternative shell
      pkgs.powershell # Microsoft pwsh shell
      pkgs.readline # readline library
      pkgs.rlwrap # readline wrapper for everything

      # -- System Fetch --
      pkgs.cpufetch # CPU info fetch
      pkgs.fastfetch # modern ASCII system summary
      pkgs.ramfetch # RAM info fetch

      # -- Text Processing --
      pkgs.choose # yet another cut/awk alternative
      pkgs.enca # detect + reencode text
      pkgs.grex # generate regexes from examples
      pkgs.grc # generic text colorizer
      pkgs.par # paragraph reformatter
      pkgs.sad # simpler sed alternative
      pkgs.sd # intuitive sed alternative
      pkgs.translate-shell # translate CLI used inside menus

      # -- TUI / Prompts --
      pkgs.gum # TUIs for shell prompts/menus
      pkgs.peaclock # animated TUI clock (used in panels)

      # -- Utilities --
      pkgs.amfora # Gemini/Gopher terminal client for text browsing
      pkgs.dcfldd # dd with progress/hash
      pkgs.dust # better du
      pkgs.erdtree # modern tree
      pkgs.eza # modern 'ls' replacement
      pkgs.gemini-cli # Google Gemini prompt CLI with streaming UI beats curl wrappers
      pkgs.libnotify # notify-send helper used by CLI scripts
      pkgs.moreutils # assorted unix utils (sponge, etc.)
      pkgs.ncdu # interactive du
      pkgs.neg.awrit # render web pages inside Kitty
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
