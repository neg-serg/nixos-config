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
    exec ${pkgs.fvwm3}/bin/fvwm3
  '';

  # The rice's trees. Entries are per file/dir below writable parent
  # directories: fvwm keeps its pid file and the FvwmCommand socket in
  # $FVWM_USERDIR, volume.sh a lock file next to the scripts and DockBarX a
  # log/state dir, so those three parents are real (tmpfiles-created) dirs rather
  # than links into the store. Files *below a symlinked parent* are also what
  # makes systemd-tmpfiles bail out with "unsafe path transition" (exit 73 =
  # CANTCREAT), so the parents must exist before nix-maid links into them.
  scriptFiles = [
    "adbfix"
    "backlight.sh"
    "dunst"
    "fvwm.sh"
    "lock"
    "music-art"
    "prime-mc.sh"
    "shot.sh"
    "speaker.sh"
    "test.py"
    "tint2-fix"
    "volume.sh"
  ];

  configPaths = [
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

  leaf = sub: p: lib.nameValuePair "${sub}/${p}" { source = "${rice}/home/${sub}/${p}"; };
  scriptPair = f: lib.nameValuePair ".scripts/${f}" { source = "${rice}/home/.scripts/${f}"; };

  homeFiles =
    (lib.listToAttrs (map scriptPair scriptFiles))
    // (lib.listToAttrs (
      map (leaf ".fvwm") [
        "config"
        "icons"
      ]
    ))
    // (lib.genAttrs configPaths (p: {
      source = "${rice}/home/${p}";
    }));
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
    # Writable parents of the rice files linked by nix-maid: fvwm keeps its pid
    # file and the FvwmCommand socket in $FVWM_USERDIR, volume.sh a lock file
    # next to the scripts, DockBarX a log/state dir. (Files below a *symlinked*
    # parent make systemd-tmpfiles exit 73/CANTCREAT and nix-maid's activation
    # fail, so these must be real directories.)
    "d ${homeDir}/.fvwm 0700 ${mainUser} ${mainUser} -"
    "d ${homeDir}/.scripts 0700 ${mainUser} ${mainUser} -"
    "d ${homeDir}/.local/share/dockbarx 0700 ${mainUser} ${mainUser} -"
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

  # Metropolis (fvwm/eww/rofi/i3lock) and GE Inspira (conky Izar) ship inside
  # pkgs.decay-rice: nixpkgs has neither.
  fonts.packages = [ rice ];

  users.users.neg.maid.file.home = homeFiles // {
    # DockBarX's themes live in a symlinked subdir of the writable state dir.
    ".local/share/dockbarx/themes" = {
      source = "${rice}/home/.local/share/dockbarx/themes";
    };
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
