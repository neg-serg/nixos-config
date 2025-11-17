{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  hasHishtory = pkgs ? hishtory;
  mkBool = desc: default: (lib.mkEnableOption desc) // {inherit default;};
  groups = rec {
    # Text/formatting/regex/CSV/TOML tools
    text = [
      pkgs.choose # yet another cut/awk alternative
      pkgs.enca # reencode files based on content
      pkgs.grex # generate regexes from examples
      pkgs.miller # awk/cut/join alternative for CSV/TSV/JSON
      pkgs.par # paragraph reformatter (fmt++)
      pkgs.sad # simpler sed alternative
      pkgs.sd # intuitive sed alternative
      pkgs.taplo # TOML toolkit (fmt, lsp, lint)
    ];

    # Filesystems, archives, hashing, mass rename, duplication
    fs = [
      pkgs.convmv # convert filename encodings
      pkgs.czkawka # find duplicates/similar files
      pkgs.dcfldd # dd with progress/hash
      pkgs.massren # massive rename utility
      pkgs.ouch # archive extractor/creator
      pkgs.patool # universal archive unpacker (python)
      pkgs.ranger # file manager (needed for termfilechooser)
      pkgs.rhash # hash sums calculator
    ];

    # Networking, cloud CLIs, URL tooling
    net = [
      pkgs.kubectx # fast switch Kubernetes contexts
      pkgs.scaleway-cli # Scaleway cloud CLI
      pkgs.speedtest-cli # internet speed test
      pkgs.urlscan # extract URLs from text
      pkgs.urlwatch # watch pages for changes
      pkgs.zfxtop # Cloudflare/ZFX top-like monitor
      pkgs.newsraft # terminal RSS/Atom feed reader
    ];

    # System info and observability
    obs = [
      pkgs.below # BPF-based system history
      pkgs.bpftrace # high-level eBPF tracer
      pkgs.lnav # log file navigator
      pkgs.viddy # modern watch with history
    ];
    sys = [
      pkgs.cpufetch # CPU info fetch
      pkgs.ramfetch # RAM info fetch
    ];

    # Dev helpers, diffs, automation, navigation
    dev = [
      pkgs.babashka # native Clojure scripting runtime
      # pkgs.diffoscope # deep diff for many formats
      pkgs.diff-so-fancy # human-friendly git diff pager
      pkgs.entr # run commands on file change
      pkgs.expect # automate interactive TTY programs
      # fasd removed in favor of zoxide
      pkgs.mergiraf # AST-aware git merge driver
      pkgs.zoxide # smarter cd with ranking
    ];
  };
in {
  options.features.cli = {
    text = mkBool "enable text/formatting/CSV/TOML tools" true;
    fs = mkBool "enable filesystem/archive/hash/mass-rename tools" true;
    net = mkBool "enable network/cloud/URL tools" true;
    obs = mkBool "enable observability/log tools" true;
    sys = mkBool "enable system fetch utilities" true;
    dev = mkBool "enable dev helpers/diffs/automation" true;
    icedteaWeb.enable = mkBool "enable IcedTea Web (netx) and user config" false;
  };
  imports = [
    ./core-tools.nix # fd, ripgrep, direnv, shell helpers
    ./bat.nix # better cat
    ./broot.nix # nested fuzzy finding
    ./btop.nix
    ./fastfetch.nix
    ./nushell.nix
    ./aliae.nix
    ./config-links.nix # dircolors, f-sy-h, zsh, inputrc
    ./amfora.nix
    ./icedtea-web.nix
    ./dosbox.nix
    ./pretty-printer.nix
    ./fzf.nix
    ./nix-index-db.nix
    ./cnf-fast.nix
    ./tmux.nix
    ./tig.nix
    ./yazi.nix
  ];
  config = lib.mkMerge [
    {
      programs = {
        bat.enable = true; # ensure bat present for cat alias
        "fabric-ai".enable = true; # Fabric AI CLI
        "fabric-ai".enableYtAlias = false; # disable default yt alias to avoid conflicts
        hwatch = {enable = true;}; # better watch with history
        kubecolor = {enable = true;}; # kubectl colorizer
        nix-search-tv = {enable = true;}; # fast search for nix packages
        numbat = {enable = true;}; # fancy scientific calculator
        television = {enable = true;}; # yet another fuzzy finder
        tray-tui = {enable = true;}; # system tray in your terminal
        visidata = {enable = true;}; # interactive multitool for tabular data
      };
      home.packages = config.lib.neg.pkgsList (
        (config.lib.neg.mkEnabledList config.features.cli groups)
        ++ [
          pkgs.tealdeer # tldr replacement written in Rust
          pkgs.neg.comma # run commands from nixpkgs by name (",") — local variant from overlay
          pkgs.kubectl # Kubernetes CLI
          pkgs.kubernetes-helm # Helm package manager
          pkgs.erdtree # modern tree
          pkgs.pigz # parallel gzip backend
          pkgs.pbzip2 # parallel bzip2 backend
          pkgs.fish # alternative shell
          pkgs.powershell # pwsh
        ]
        ++ lib.optionals hasHishtory [pkgs.hishtory]
      );
    }
    (lib.mkIf hasHishtory {
      home.sessionVariables.HISHTORY_ZSH_CONFIG = "${pkgs.hishtory}/share/hishtory/config.zsh";
      home.activation.ensureHishtoryDir =
        config.lib.neg.mkEnsureRealDir "${config.home.homeDirectory}/.hishtory";
    })
    (lib.mkIf (! hasHishtory) {
      warnings = [
        "hishtory is unavailable in the pinned nixpkgs; skip CLI integration."
      ];
    })
  ];
}
