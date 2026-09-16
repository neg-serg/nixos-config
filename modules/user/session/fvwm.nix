# FVWM "An essence of decay" — X11 rice session (upstream: syndrizzle/hotfiles,
# branch `fvwm`). files/x11/README.md lists what is vendored and which FHS paths
# had to be rewritten.
#
# The rice is X11-only while odin runs Wayland: features.gui.fvwm.enable turns
# services.xserver on (hosts/odin/services/policy.nix keeps X off otherwise) and
# installs pkgs.decay-rice, whose share/xsessions/fvwm-decay.desktop is read by
# the greetd/quickshell greeter (/usr/share/xsessions comes from the profile).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.gui.fvwm;
  rice = pkgs.decay-rice;
  mainUser = config.lib.neg.mainUser;
  # Plain "/home/<name>": config.lib.neg.homeDir dereferences users.users.<name>.home,
  # which would make the tmpfiles rules below part of that fixpoint.
  homeDir = "/home/${mainUser}";

  # X clients of the session: upstream ~/.xinitrc with fvwm3 as the WM. $XINITRC
  # already points at $XDG_CONFIG_HOME/xinit/xinitrc
  # (modules/user/nix-maid/cli/envs.nix); startx is exec'd by
  # bin/start-fvwm-decay from pkgs.decay-rice.
  xinitrc = ''
    #!/bin/sh
    [[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources
    if [ -d /etc/X11/xinit/xinitrc.d ] ; then
     for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
      [ -x "$f" ] && . "$f"
     done
     unset f
    fi
    # odin's 4K panel gets the 1080p logical desktop the rice was designed for.
    rice-display
    # -f: the config comes from the immutable ~/.fvwm; $FVWM_USERDIR (set by
    # start-fvwm-decay) only carries fvwm's pid file and the FvwmCommand socket.
    exec ${pkgs.fvwm3}/bin/fvwm3 -f "$HOME/.fvwm/config"
  '';

  # Trees of the rice, one symlink per tree: nix-maid links them straight from
  # the store, and systemd-tmpfiles refuses to manage files *below a symlinked
  # parent* ("unsafe path transition", exit 73/CANTCREAT, which fails nix-maid's
  # activation). Everything the rice needs to write is redirected instead:
  # fvwm's pid file/socket to $FVWM_USERDIR, volume.sh's lock file to
  # $XDG_RUNTIME_DIR, DockBarX's log/state to a real ~/.local/share/dockbarx
  # (created by the tmpfiles rules below).
  homeTrees = [
    ".fvwm"
    ".scripts"
    ".config/eww"
    ".config/conky"
    ".config/dunst"
    ".config/rofi"
    ".config/jgmenu"
    ".config/tint2"
    ".config/albert"
    ".config/redshift"
    ".config/networkmanager-dmenu"
    ".config/qt5ct"
    ".config/picom.conf"
    ".config/kitty-decay"
  ];

  homeFiles = lib.genAttrs homeTrees (p: {
    source = "${rice}/home/${p}";
  });

  # DockBarX keeps its preferences in dconf (upstream's dotfiles do not carry
  # them): a starter set of pinned launchers. An entry is "<identifier>;<path to
  # .desktop>"; the empty identifier makes DockBarX derive it from the desktop
  # file itself.
  dockLaunchers = [
    "kitty" # terminal of the rice
    "thunar" # file manager from the desktop menu
    "vivaldi-stable" # browser (the rice's firefox/brave entries are shimmed to Vivaldi)
    "mpv" # media player
  ];
  dockLauncherEntries = map (
    name: ";/run/current-system/sw/share/applications/${name}.desktop"
  ) dockLaunchers;
in
lib.mkIf cfg.enable {
  services.xserver.enable = true;
  # Mirror of the Hyprland kb_layout ("us,ru"); switching stays with kanata.
  services.xserver.xkb.layout = "us,ru";

  systemd.tmpfiles.rules = [
    # The rice Execs the FHS path of the mate-polkit agent verbatim; provide the
    # path instead of patching files/x11/rice/home/.fvwm/config.
    "d /usr/lib 0755 root root -" # NixOS has no /usr/lib
    "d /usr/lib/mate-polkit 0755 root root -"
    "L+ /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 - - - - ${pkgs.mate-polkit}/libexec/polkit-mate-authentication-agent-1"
    # DockBarX logs and stores state below ~/.local/share/dockbarx, so that tree
    # is a real directory (not a nix-maid link: files below a symlinked parent
    # make systemd-tmpfiles exit 73/CANTCREAT and fail nix-maid's activation) and
    # the rice's theme archives are linked into it file by file. DockBarX reads
    # only themes/**/*.tar.gz, so the extracted copies of upstream stay unused.
    "d ${homeDir}/.local/share/dockbarx 0700 ${mainUser} ${mainUser} -"
    "d ${homeDir}/.local/share/dockbarx/themes 0700 ${mainUser} ${mainUser} -"
    "d ${homeDir}/.local/share/dockbarx/themes/dock 0700 ${mainUser} ${mainUser} -"
    "d ${homeDir}/.local/share/dockbarx/themes/popup_styles 0700 ${mainUser} ${mainUser} -"
    "L+ ${homeDir}/.local/share/dockbarx/themes/Decay.tar.gz - - - - ${rice}/home/.local/share/dockbarx/themes/Decay.tar.gz"
    "L+ ${homeDir}/.local/share/dockbarx/themes/dock/invisible.tar.gz - - - - ${rice}/home/.local/share/dockbarx/themes/dock/invisible.tar.gz"
    "L+ ${homeDir}/.local/share/dockbarx/themes/popup_styles/Decay.tar.gz - - - - ${rice}/home/.local/share/dockbarx/themes/popup_styles/Decay.tar.gz"
  ];

  environment.systemPackages = [
    rice # vendored rice dotfiles, shims (python/albert/parcellite/light) and the session entry point
    pkgs.decay-gtk-theme # GTK3 Decay theme (GTK_THEME=decay in the session)
    pkgs.fvwm3 # window manager (fvwm2 syntax; the config uses fvwm3 modifiers)
    pkgs.picom # compositor started by fvwm's InitFunction
    pkgs.eww # bottom panel + widgets (bar, notifications, system menu)
    pkgs.rofi # application menu, window switcher, screenshot menu
    pkgs.dunst # notification daemon
    pkgs.dockbarx # dock (dockx), Decay theme in ~/.local/share/dockbarx
    pkgs.jgmenu # desktop menu (jgmenu_run)
    pkgs.nitrogen # wallpaper restore (nitrogen --restore)
    pkgs.conky # desktop widgets (Izar theme, started by fvwm)
    pkgs.i3lock-color # lock screen: ~/.scripts/lock uses i3lock-color flags
    pkgs.maim # screenshots in ~/.scripts/shot.sh
    pkgs.xclip # clipboard for shot.sh
    pkgs.xdotool # active-window lookup for shot.sh and tint2-fix
    pkgs.wmctrl # workspace queries behind the eww workspace widget
    pkgs.pamixer # volume control in ~/.scripts/volume.sh
    pkgs.playerctl # media keys and the eww music widgets
    pkgs.acpi # battery readout of the eww bar widget
    pkgs.util-linux # rfkill for the bar widgets' wifi/bluetooth toggles
    pkgs.bluez # bluetoothctl behind the bar's bluetooth widget
    pkgs.networkmanager # nmcli behind the bar's wifi widget
    pkgs.imagemagick # `convert` in the eww scripts
    pkgs.curl # weather widget
    pkgs.jq # JSON parsing in the eww scripts
    pkgs.bc # arithmetic in ~/.scripts/backlight.sh
    pkgs.mate-polkit # polkit authentication agent for the X session
    pkgs.xfce4-power-manager # power management, started by fvwm's InitFunction
    pkgs.thunar # file manager from the desktop menu
    pkgs.redshift # colour temperature daemon + eww widget
    pkgs.papirus-icon-theme # icon theme of the rice (Papirus-Dark)
    pkgs.libsForQt5.qt5ct # Qt platform theme (QT_QPA_PLATFORMTHEME=qt5ct)
    pkgs.xinit # startx used by the session entry point
    pkgs.xauth # X cookie needed by startx for a non-root X server
    pkgs.xrdb # merges ~/.Xresources (Xft.dpi, cursor theme)
    pkgs.xrandr # screen geometry in ~/.scripts/shot.sh
    pkgs.xprop # _NET_CLIENT_LIST read by the rofi window switcher
    pkgs.xwininfo # session inspection (window tree of the X display)
  ];

  # DockBarX reads its dock style and launchers from dconf; seed the rice's ones
  # (see dockLaunchers). Locks are not used, so the GUI can still change them.
  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings."org/dockbarx/dockbarx" = {
          # themes/dock/invisible.tar.gz — the dock style the rice shipped (its
          # internal name is Decay).
          theme-file = lib.gvariant.mkString "invisible.tar.gz";
          # themes/popup_styles/Decay.tar.gz
          popup-style-file = lib.gvariant.mkString "Decay";
          # lib.gvariant.mkString keeps the quotes out of the value (a plain
          # string in `settings` ends up stored *with* quotes, see the
          # gtk-theme key of modules/user/nix-maid/gui/theme.nix).
          launchers = lib.gvariant.mkArray (map lib.gvariant.mkString dockLauncherEntries);
        };
      }
    ];
  };

  # Metropolis (fvwm/eww/rofi/i3lock) and GE Inspira (conky Izar) ship inside
  # pkgs.decay-rice: nixpkgs has neither. JetBrainsMono Nerd Font is the rice's
  # kitty font_family (kitty falls back to Iosevka without it).
  fonts.packages = [
    rice # Metropolis (fvwm/eww/rofi) + GE Inspira (conky Izar) from the payload
    pkgs.nerd-fonts.jetbrains-mono # the rice's kitty font_family (JetBrainsMono Nerd Font)
  ];

  users.users.neg.maid.file.home = homeFiles // {
    ".Xresources" = {
      source = "${rice}/home/.Xresources";
    };
    ".wallpapers" = {
      source = "${rice}/home/.wallpapers";
    };
    # ~/.icons is a symlink to ~/.local/share/icons on this host, so the cursor
    # theme and the notification icons land there.
    ".local/share/icons/Xcursor-Pro-Decay" = {
      source = "${rice}/share/icons/Xcursor-Pro-Decay";
    };
    ".local/share/icons/tmp" = {
      source = "${rice}/home/.icons/tmp";
    };
    ".config/xinit/xinitrc".text = xinitrc;
    # Nitrogen's config is read-only here: `nitrogen --restore` (fvwm's
    # StartFunction) only reads it; changing the wallpaper means editing the
    # file list in ~/.wallpapers and the `file=` below.
    ".config/nitrogen/nitrogen.cfg".text = ''
      [nitrogen]
      view=icon
      recurse=true
      sort=alpha
      icon_caps=false
      dirs=$HOME/.wallpapers;
    '';
    # Wallpaper of the rice; the lock screen uses ~/.wallpapers/lock.png.
    ".config/nitrogen/bg-saved.cfg".text = ''
      [xin_-1]
      file=${rice}/home/.wallpapers/dark-decay-void.jpg
      mode=5
      bgcolor=#000000
    '';
  };
}
