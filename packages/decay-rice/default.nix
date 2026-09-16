# FVWM "An essence of decay" — NixOS repackaging of the upstream dotfiles
# (github.com/syndrizzle/hotfiles, branch `fvwm`, commit edc3359, 2022-08-19).
#
# The rice files are tracked verbatim in files/x11/rice/; this derivation only
#   * rewrites the FHS paths NixOS cannot provide (list: files/x11/README.md),
#   * ships shims for the commands the rice calls that nixpkgs does not carry
#     (python, albert, parcellite, light),
#   * adds the session entry point (share/xsessions/fvwm-decay.desktop plus
#     bin/start-fvwm-decay) read by the greetd greeter.
#
# No `meta`: local repackaging of files already tracked in this repo (same as
# the python3.withPackages environments, see packages/AGENTS.md).
{
  runCommandLocal,
  writeShellScriptBin,
  brightnessctl,
  clipmenu,
  fvwm3,
  atk,
  gdk-pixbuf,
  glib,
  gobject-introspection, # xlib-2.0 typelib, required by GdkX11 in the X session
  gtk3,
  harfbuzz,
  imagemagick,
  less,
  lib,
  pango,
  papirus-icon-theme,
  pamixer,
  playerctl,
  python3,
  rofi,
  xinit,
  yaru-theme,
}:
let
  rice = ../../files/x11/rice;

  # Python behind the eww widgets (scripts/logger.py, getInfo, cache.py,
  # handlers.py): praw (Reddit quotes), requests (weather), dbus-python
  # (notifications over DBus), pygobject3 (GLib/Playerctl introspection),
  # wand (music-art thumbnails through ImageMagick).
  ewwPython = python3.withPackages (ps: [
    ps.dbus-python
    ps.pygobject3
    ps.praw
    ps.requests
    ps.wand
  ]);

  # Every typelib the eww widgets pull in through Gtk (Gtk -> Atk/Pango/
  # GdkPixbuf/GdkX11, plus playerctl and the xlib namespace GdkX11 wants in an X
  # session). Missing entries show up as "Namespace X not available" at runtime.
  # lib.getLib: the typelibs live in the library output (pango's default output
  # resolves to -bin, which has an empty girepository dir).
  widgetTypelibs = lib.makeSearchPath "lib/girepository-1.0" (
    map lib.getLib [
      atk
      gdk-pixbuf
      glib
      gobject-introspection
      gtk3
      harfbuzz
      pango
      playerctl
    ]
  );

  # Upstream calls bare `python`, `albert`, `parcellite` and `light`. The shims
  # below keep the vendored scripts and ~/.fvwm/config byte-identical.
  pythonShim = writeShellScriptBin "python" ''
    # GI typelibs the widgets import; playerctl/magick arrive through PATH.
    export GI_TYPELIB_PATH="${widgetTypelibs}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    export PATH="${playerctl}/bin:${imagemagick}/bin''${PATH:+:$PATH}"
    exec ${ewwPython}/bin/python3 "$@"
  '';

  albertShim = writeShellScriptBin "albert" ''
    # Albert (the rice's launcher) is unpackaged; rofi drun is the stand-in.
    exec ${rofi}/bin/rofi -show drun "$@"
  '';

  firefoxShim = writeShellScriptBin "firefox" ''
    # The rice hardcodes firefox (Super+b and dunst's URL handler); this host runs
    # Vivaldi (features.web.vivaldi), so keep the config verbatim and redirect.
    exec vivaldi "$@"
  '';

  parcelliteShim = writeShellScriptBin "parcellite" ''
    # Clipboard-history daemon → clipmenud.
    exec ${clipmenu}/bin/clipmenud
  '';

  lightShim = writeShellScriptBin "light" ''
    # `light` was removed from nixpkgs; implement the subset backlight.sh uses.
    set -eu
    case "''${1:--G}" in
      -G)
        ${brightnessctl}/bin/brightnessctl -m | cut -d, -f4 | tr -d '%'
        ;;
      -A)
        ${brightnessctl}/bin/brightnessctl set "+''${2:?}%"
        ;;
      -U)
        ${brightnessctl}/bin/brightnessctl set "''${2:?}%-"
        ;;
      -S)
        ${brightnessctl}/bin/brightnessctl set "''${2:?}%"
        ;;
      *)
        echo "light shim: unsupported argument: ''${1:--G}" >&2
        exit 2
        ;;
    esac
  '';
in
runCommandLocal "decay-rice" { } ''
  mkdir -p $out/bin $out/share/fonts/truetype $out/share/icons $out/share/jgmenu $out/share/xsessions

  cp -r ${rice}/home $out/home
  chmod -R u+w $out/home

  # --- FHS → store rewrites (each one documented in files/x11/README.md) ----
  substituteInPlace $out/home/.scripts/volume.sh \
    --replace-fail "/usr/bin/pamixer" "${pamixer}/bin/pamixer"
  substituteInPlace $out/home/.scripts/fvwm.sh \
    --replace-fail "/usr/bin/fvwm" "${fvwm3}/bin/fvwm3"
  substituteInPlace $out/home/.scripts/dunst/sound-normal.sh \
    --replace-fail "/usr/share/sounds/Yaru" "${yaru-theme}/share/sounds/Yaru"
  substituteInPlace $out/home/.scripts/dunst/sound-critical.sh \
    --replace-fail "/usr/share/sounds/Yaru" "${yaru-theme}/share/sounds/Yaru"
  substituteInPlace $out/home/.config/dunst/dunstrc \
    --replace-fail "/usr/share/icons/gnome/128x128/status/" "${papirus-icon-theme}/share/icons/Papirus-Dark/48x48/status/" \
    --replace-fail "/usr/share/icons/gnome/128x128/devices/" "${papirus-icon-theme}/share/icons/Papirus-Dark/48x48/devices/" \
    --replace-fail "dmenu = /usr/bin/dmenu" "dmenu = ${rofi}/bin/rofi -dmenu" \
    --replace-fail "browser = /usr/bin/firefox -new-tab" "browser = firefox"
  substituteInPlace $out/home/.config/eww/scripts/getInfo \
    --replace-fail "/usr/share/icons/Papirus" "${papirus-icon-theme}/share/icons/Papirus"
  substituteInPlace $out/home/.config/eww/scripts/utils.py \
    --replace-fail "/usr/share/icons/Papirus-Dark" "${papirus-icon-theme}/share/icons/Papirus-Dark"
  substituteInPlace $out/home/.config/kitty-decay/kitty.conf \
    --replace-fail "usr/bin/less" "${less}/bin/less"
  # ~/.scripts stays a read-only link into the store, so volume.sh keeps its lock
  # file in the runtime dir instead of next to the script (upstream:
  # lockfile=~/.scripts/volume-lockfile).
  substituteInPlace $out/home/.scripts/volume.sh \
    --replace-fail 'lockfile=~/.scripts/volume-lockfile' 'lockfile="$XDG_RUNTIME_DIR/fvwm-volume.lock"'
  # logger.py uses GNU env's --split-string form, which patchShebangs cannot
  # resolve; point it at the python shim (copied into $out/bin below).
  # The eww notification logger asks DBus for notification *eavesdropping*;
  # dbus-broker (services.dbus.implementation = "broker" on this host) rejects any
  # `eavesdrop=` key in a match rule with MatchRuleInvalid and upstream's script
  # then dies with a traceback on every session start. Comment the key out: the
  # rule stays valid and the widget survives (it just receives nothing, i.e. no
  # notification history on this host).
  substituteInPlace $out/home/.config/eww/scripts/cache.py \
    --replace-fail '"eavesdrop": "true",  # https://bugs.freedesktop.org/show_bug.cgi?id=39450' '# "eavesdrop": "true",  # NixOS: dbus-broker rejects eavesdropping'
  substituteInPlace $out/home/.config/eww/scripts/logger.py \
    --replace-fail "#!/usr/bin/env --split-string=python -u" "#!${pythonShim}/bin/python -u"
  substituteInPlace $out/home/.config/jgmenu/*.csv \
    --replace-fail "/usr/share/jgmenu" "$out/share/jgmenu" \
    --replace-fail "Web Browser,brave" "Web Browser,vivaldi" \
    --replace-fail "Website, firefox http" "Website, vivaldi http" \
    --replace-fail "Documentation, brave http" "Documentation, vivaldi http"


  # /bin/bash and /usr/bin/env python do not exist on NixOS. $out/bin holds the
  # python shim, so `env python` and `env python3` resolve to the widget stack.
  cp ${pythonShim}/bin/python $out/bin/python
  cp ${albertShim}/bin/albert $out/bin/albert
  cp ${parcelliteShim}/bin/parcellite $out/bin/parcellite
  cp ${lightShim}/bin/light $out/bin/light
  cp ${firefoxShim}/bin/firefox $out/bin/firefox
  PATH="$out/bin:$PATH" patchShebangs $out/home

  # --- DockBarX theme archives ---------------------------------------------
  # Upstream ships these three as .tar.gz, which .gitignore refuses to track
  # ("no compressed blobs"), so the extracted trees live in
  # files/x11/rice/dockbarx-themes and are packed back here. DockBarX only looks
  # at themes/**/*.tar.gz, hence the archive form is required.
  mkdir -p $out/home/.local/share/dockbarx/themes/dock $out/home/.local/share/dockbarx/themes/popup_styles
  for pair in \
    "${rice}/dockbarx-themes/themes-root-Decay:Decay.tar.gz" \
    "${rice}/dockbarx-themes/dock-invisible:dock/invisible.tar.gz" \
    "${rice}/dockbarx-themes/popup-styles-Decay:popup_styles/Decay.tar.gz"; do
    src="''${pair%%:*}"; dst="''${pair##*:}"
    # --transform strips the ./ prefix: DockBarX looks up members by plain name
    # (tar.extractfile("config")).
    ( cd "$src" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --transform 's,^\./,,' -czf "$out/home/.local/share/dockbarx/themes/$dst" ./* )
  done
  tar tzf $out/home/.local/share/dockbarx/themes/Decay.tar.gz | head -1

  # --- fonts, cursor theme, jgmenu icons -----------------------------------
  # Metropolis (fvwm/eww/rofi/i3lock) and GE Inspira (conky Izar) are not in
  # nixpkgs; the cursor theme is XCURSOR_THEME=Xcursor-Pro-Decay.
  cp ${rice}/share/fonts/*.ttf $out/share/fonts/truetype/
  cp -r ${rice}/share/icons/Xcursor-Pro-Decay $out/share/icons/
  # prepend.csv references the menu icons by absolute path.
  cp -r ${rice}/share/jgmenu/MenuIcons $out/share/jgmenu/

  # --- X11 session entry point (greetd greeter reads Exec=) ----------------
  cat > $out/bin/start-fvwm-decay <<'START'
  #!/bin/sh
  # First process of the FVWM rice session: greetd's session-wrapper execs the
  # Exec= line of share/xsessions/fvwm-decay.desktop without a shell, so the
  # session environment is set up here.
  set -eu

  export XDG_SESSION_TYPE=x11
  export XDG_CURRENT_DESKTOP=FVWM
  export DESKTOP_SESSION=fvwm-decay

  # The rice ships its own kitty config (decay palette); the Wayland session
  # keeps using ~/.config/kitty untouched.
  export KITTY_CONFIG_DIRECTORY="$HOME/.config/kitty-decay"
  export XCURSOR_THEME=Xcursor-Pro-Decay
  export XCURSOR_SIZE=28
  export GTK_THEME=decay
  export QT_QPA_PLATFORMTHEME=qt5ct

  # fvwm writes its pid file and the FvwmCommand socket into $FVWM_USERDIR, which
  # must not be the rice's ~/.fvwm (that one is an immutable link into the store).
  export FVWM_USERDIR="''${XDG_STATE_HOME:-$HOME/.local/state}/fvwm"
  mkdir -p "$FVWM_USERDIR"

  # `volume.sh` keeps a lock file next to the other runtime state.
  export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp}"


  # shims (python/albert/parcellite/light) + the X tools the rice Execs.
  export PATH="@out@/bin:$PATH"

  # $XINITRC ($XDG_CONFIG_HOME/xinit/xinitrc) merges ~/.Xresources and execs fvwm3.
  exec ${xinit}/bin/startx
  START
  substituteInPlace $out/bin/start-fvwm-decay --replace-fail "@out@" "$out"
  chmod +x $out/bin/start-fvwm-decay
  # --- logical 1920x1080 desktop (what the rice was designed for) ----------
  # Upstream README: built for a 1920x1080 laptop at Xft.dpi 120. odin's panel is
  # 3840x2160, so a 4K output gets a 1080p logical desktop through a GPU
  # transform — the geometry in ~/.fvwm/config and the eww bar stay exact.
  cat > $out/bin/rice-display <<'DISPLAY'
  #!/bin/sh
  # Called from $XDG_CONFIG_HOME/xinit/xinitrc after the X server is up.
  set -u
  for out in $(xrandr --query | sed -n 's/^\([^ ]*\) connected.*/\1/p'); do
    if xrandr --query | sed -n "/^$out connected/,/^[^ ]/p" | grep -q '3840x2160'; then
      xrandr --output "$out" --mode 3840x2160 --scale-from 1920x1080 || true
    fi
  done
  DISPLAY
  chmod +x $out/bin/rice-display

  cat > $out/share/xsessions/fvwm-decay.desktop <<EOF
  [Desktop Entry]
  Type=Application

  Name=FVWM (decay)
  Comment=FVWM3 rice "An essence of decay" (syndrizzle/hotfiles)
  Exec=$out/bin/start-fvwm-decay
  DesktopNames=FVWM
  EOF
''
