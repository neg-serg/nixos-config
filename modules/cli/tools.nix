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

  # Available CLI tools (from stone-recipes, ported for future use):
  # pkgs.cloudflare-speed-cli # Cloudflare speed test
  # pkgs.cdrtools # CD/DVD burning tools
  # pkgs.dhcpcd # DHCP client
  # pkgs.enca # charset analyser and converter
  # pkgs.etckeeper # store /etc in git
  # pkgs.genact # nonsense activity generator
  # pkgs.gitleaks # git secret scanner
  # pkgs.gitlogue # git history viewer
  # pkgs.hunspellDicts.ru_RU # Russian hunspell dictionary
  # pkgs.iotop-c # simple top-like I/O monitor (C version)
  # pkgs.iperf3 # TCP/UDP bandwidth measurement tool
  # pkgs.mandoc # man page parser/formatter
  # pkgs.neo-matrix # matrix simulated console
  # pkgs.no-more-secrets # data decryption effect
  # pkgs.pandoc # universal document converter
  # pkgs.rebuild-detector # detects packages that need rebuild
  # pkgs.regex-tui # TUI regex tester
  # pkgs.songfetch # music-info fetcher
  # pkgs.systemd-manager-tui # systemd TUI manager
  # pkgs.tabiew # TUI for tabular data
  # pkgs.taplo-cli # TOML toolkit
  # pkgs.tokei # fast line-counting tool
  # pkgs.vale # prose linter
  # pkgs.zathura-pdf-poppler # PDF plugin for zathura

  # AUR-ported packages (from stone-recipes, available via pkgs overlay):
  # pkgs.act # run GitHub Actions locally
  # pkgs.eilmeldung # daemon for xdg-desktop-portal that handles notifications
  # pkgs.fsel # file selector for cli/tui tools
  # pkgs.ghgrab # fast download of GitHub repos
  # pkgs.gmap # terminal-based map viewer
  # pkgs.gowall # wallpaper color extractor
  # pkgs.lazytail # simple log file viewer
  # pkgs.oports # wrapper around ss -tunlp
  # pkgs.pipemixer # TUI volume control for pipewire
  # pkgs.protonup-rs # Proton-GE installer
  # pkgs.reddix # terminal-based Reddit client
  # pkgs.repeater # text repeater tool
  # pkgs.resterm # terminal-based REST client
  # pkgs.simutil # sim card utility
  # pkgs.strace-tui # TUI for strace output
  # pkgs.snixembed # proxy StatusNotifierItems as XEmbedded systemtray
  # pkgs.tanin # ambient sound generator
  # pkgs.v2raya # web GUI for V2Ray proxy
  # pkgs.watchtower # TUI system resource watcher
  # pkgs.witr # TUI for WireGuard connections
  # pkgs.xdg-desktop-portal-termfilechooser-hunkyburrito # terminal file chooser portal
}
