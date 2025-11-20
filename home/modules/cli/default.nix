{
  lib,
  config,
  pkgs,
  negLib,
  ...
}:
with lib; let
  hasHishtory = pkgs ? hishtory;
  mkBool = desc: default: (lib.mkEnableOption desc) // {inherit default;};
in {
  options.features.cli = {
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
      # CLI package set now ships from modules/cli/pkgs.nix system-wide.
    }
    (lib.mkIf hasHishtory {
      home.sessionVariables.HISHTORY_ZSH_CONFIG = "${pkgs.hishtory}/share/hishtory/config.zsh";
      home.activation.ensureHishtoryDir =
        negLib.mkEnsureRealDir "${config.home.homeDirectory}/.hishtory";
    })
    (lib.mkIf (! hasHishtory) {
      warnings = [
        "hishtory is unavailable in the pinned nixpkgs; skip CLI integration."
      ];
    })
  ];
}
