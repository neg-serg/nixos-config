{
  lib,
  pkgs,
  inputs,
  config,
  ...
}: let
  mkQuickshellWrapper = import (inputs.self + "/lib/quickshell-wrapper.nix") {
    inherit lib pkgs;
  };
  quickshellPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default; # exact quickshell build for host cpu
  quickshellWrapped = mkQuickshellWrapper {qsPkg = quickshellPkg;};
  hostSystem = pkgs.stdenv.hostPlatform.system; # shorthand for current architecture
  devSpeed = config.features.devSpeed.enable or false;
  guiEnabled = config.features.gui.enable or false;
  getInputPackage = input: lib.attrByPath ["packages" hostSystem "default"] null input;
  iwmenuPkg = getInputPackage inputs.iwmenu;
  menuPkgs =
    if guiEnabled && !devSpeed
    then lib.filter (pkg: pkg != null) [iwmenuPkg]
    else [];
  hyprWinList = pkgs.writeShellApplication {
    # helper to list Hypr windows through rofi
    name = "hypr-win-list";
    runtimeInputs = [
      pkgs.python3 # embed interpreter so the script ships zero deps
      pkgs.wl-clipboard # pipe clipboard ops without relying on system PATH
    ];
    text = let
      tpl = builtins.readFile (inputs.self + "/home/modules/user/gui/hypr/hypr-win-list.py");
    in ''
                   exec python3 <<'PY'
      ${tpl}
      PY
    '';
  };
  localBinPackages = [
    pkgs.alsa-utils # alsamixer/amixer fallback; direct ALSA control when PipeWire drifts
    pkgs.essentia-extractor # Essentia CLI; pro audio descriptors far beyond ffmpeg
    pkgs.imagemagick # convert/mogrify workhorse; handles odd formats better than feh
    pkgs.neg.albumdetails # TagLib album metadata CLI; richer dump than mediainfo
    pkgs.neg.bpf_host_latency # BCC DNS latency tracer; deeper insight than dig/tcpdump
    pkgs.neg.music_clap # LAION-CLAP embeddings CLI; offline tagging faster than cloud AI
    pkgs.wireplumber # Lua PipeWire session mgr; more tweakable than media-session
  ];
in {
  # Wayland/Hyprland tools and small utilities
  environment.systemPackages =
    [
      # -- Audio --
      pkgs.cava # console audio visualizer for quickshell HUD
      pkgs.mpc # MPD CLI helper for local scripts
      pkgs.playerctl # MPRIS media controller for bindings

      # -- Chat / Social --
      pkgs.nchat # terminal-first Telegram client
      pkgs.tdl # Telegram CLI uploader/downloader
      pkgs.telegram-desktop # Telegram GUI client
      pkgs.vesktop # Discord (Vencord) desktop client

      # -- Clipboard --
      pkgs.cliphist # persistent Wayland clipboard history
      pkgs.wl-clip-persist # persist clipboard across app exits
      pkgs.wl-clipboard # wl-copy / wl-paste

      # -- Dialogs / Automation --
      pkgs.espanso # text expander daemon
      pkgs.kdePackages.kdialog # Qt dialog helper
      pkgs.wtype # fake typing for Wayland automation
      pkgs.ydotool # uinput automation helper (autoclicker, etc.)

      # -- Fonts --
      pkgs.cantarell-fonts # UI font for panels/widgets

      # -- Hyprland --
      hyprWinList # injects rust-based win switcher bound in Hypr
      inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
      pkgs.hyprcursor # modern cursor theme format for Hyprland
      pkgs.hypridle # idle daemon for Hyprland sessions
      pkgs.hyprlandPlugins.hy3 # tiling plugin for Hyprland
      pkgs.hyprpicker # color picker for Wayland/Hyprland
      pkgs.hyprpolkitagent # Wayland-friendly polkit agent
      pkgs.hyprprop # Hyprland property helper (xprop-like)
      pkgs.hyprutils # assorted Hyprland utilities
      pkgs.pyprland # Hyprland plugin/runtime helper

      # -- Notifications --
      pkgs.dunst # notification daemon + dunstctl

      # -- Power --
      pkgs.upower # power management daemon for laptops/desktops

      # -- Proxy --
      pkgs.hiddify-app # Hiddify proxy client

      # -- Qt --
      pkgs.hyprland-qt-support # Qt integration helpers for Hyprland
      pkgs.hyprland-qtutils # Qt extras (hyprland-qt-helper)
      pkgs.kdePackages.qt5compat # Qt6 QtQuick bridge
      pkgs.kdePackages.qt6ct # Qt6 configuration utility
      pkgs.kdePackages.qtdeclarative # QtDeclarative (QML runtime)
      pkgs.kdePackages.qtimageformats # extra Qt image formats
      pkgs.kdePackages.qtmultimedia # Qt multimedia modules
      pkgs.kdePackages.qtpositioning # Qt positioning (sensors)
      pkgs.kdePackages.qtquicktimeline # Qt timeline module
      pkgs.kdePackages.qtsensors # Qt sensors module
      pkgs.kdePackages.qtsvg # Qt SVG backend
      pkgs.kdePackages.qttools # Qt utility tooling
      pkgs.kdePackages.qttranslations # Qt translations set
      pkgs.kdePackages.qtvirtualkeyboard # Qt virtual keyboard
      pkgs.kdePackages.qtwayland # Qt Wayland plugin
      pkgs.kdePackages.syntax-highlighting # KSyntaxHighlighting for QML
      pkgs.qt6.qtimageformats # supplemental Qt6 image formats
      pkgs.qt6.qtsvg # supplemental Qt6 SVG support

      # -- Quickshell --
      quickshellWrapped # wrapped quickshell binary with required envs

      # -- Screenshot / Recording --
      pkgs.grim # raw screenshot helper for clip wrappers
      pkgs.grimblast # Hyprland-friendly screenshots (grim+slurp+wl-copy)
      pkgs.slurp # select regions for grim/wlroots compositors
      pkgs.swappy # screenshot editor (optional)
      pkgs.wf-recorder # screen recording

      # -- Sharing --
      pkgs.localsend # AirDrop-like local file sharing

      # -- SVG / Graphics --
      pkgs.librsvg # rsvg-convert for assets
      pkgs.libxml2 # xmllint for SVG validation

      # -- Terminal --
      pkgs.kitty # primary GUI terminal emulator
      pkgs.kitty-img # inline image helper for Kitty
      pkgs.warp-terminal # Warp GPU-accelerated terminal with modern UI

      # -- Theme / Wallpaper --
      pkgs.gowall # generate palette from wallpaper
      pkgs.matugen # wallpaper-driven palette/matcap generator
      pkgs.matugen-themes # template pack for Matugen output files
      pkgs.swaybg # simple wallpaper setter
      pkgs.swww # Wayland wallpaper daemon

      # -- Viewer --
      pkgs.zathura # lightweight document viewer for rofi wrappers

      # -- Wayland Utils --
      pkgs.dragon-drop # drag-n-drop from console
      pkgs.networkmanager # CLI nmcli helper for panels
      pkgs.waybar # Wayland status bar
      pkgs.waypipe # Wayland remoting (ssh -X like)
      pkgs.wev # xev for Wayland
      pkgs.xorg.xeyes # track eyes for your cursor
    ]
    ++ menuPkgs
    ++ lib.optionals guiEnabled localBinPackages;
}
