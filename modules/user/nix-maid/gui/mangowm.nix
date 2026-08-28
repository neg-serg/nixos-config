{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.gui.mangowm;

  # MangoWM config — ported from Hyprland (files/gui/hypr/hyprland.lua).
  # wl-only branch: wlroots Vulkan renderer (ICC/HDR capable), no scenefx
  # effects. HDR stays OFF in this session by design — run a separate HDR
  # session (e.g. Hyprland on another TTY) so it never degrades this one.
  configConf = ''
    # --- Monitor: DP-2 3840x2160@240 scale 2 VRR; DP-1 disabled ---
    # Colors stay sRGB: the linear->P3 ICC output transform (wlroots 0.20
    # scene path) shifts the whole desktop (brighter/oversaturated) for
    # non-color-managed clients. Wide gamut lives in the gamescope HDR session.
    monitorrule=name:DP-2, width:3840, height:2160, refresh:240, scale:2, vrr:1, x:0, y:0
    monitorrule=name:DP-1, disable:1

    # --- Keyboard: us,ru like Hyprland (input.kb_layout). SUPER+S is bound to
    # switch_keyboard_layout below; with a single layout that bind is a no-op. ---
    xkb_rules_layout=us,ru

    # --- Environment ---
    env=CLUTTER_BACKEND,wayland
    env=ELECTRON_OZONE_PLATFORM_HINT,auto
    env=GDK_BACKEND,wayland
    env=GDK_SCALE,2
    env=MOZ_ENABLE_WAYLAND,1
    env=QT_AUTO_SCREEN_SCALE_FACTOR,1
    env=QT_ENABLE_HIGHDPI_SCALING,1
    env=QT_QPA_PLATFORM,wayland;xcb
    env=QT_QPA_PLATFORMTHEME,qt6ct
    env=QT_STYLE_OVERRIDE,kvantum
    env=SDL_VIDEODRIVER,wayland,x11
    env=XCURSOR_SIZE,23
    env=XCURSOR_THEME,Alkano-aio
    env=XDG_CURRENT_DESKTOP,mango
    env=XDG_SESSION_DESKTOP,mango
    env=XDG_SESSION_TYPE,wayland

    # --- Autostart (from hyprland.lua hyprland.start; quickshell stays Hyprland-only) ---
    exec-once=systemctl --user start wl-daemon.service
    exec-once=wl-restore
    exec-once=kitty --single-instance --class term
    exec-once=telegram-desktop
    exec-once=vesktop
    exec-once=wl-clip-persist --clipboard regular
    exec-once=zsh -c 'pkill "wl-paste --watch cliphist store"; wl-paste --watch cliphist store'
    exec-once=nicotine -s
    exec-once=systemctl --user start --no-block vicinae.service

    # --- General ---
    borderpx=1
    bordercolor=0x002859ff
    focuscolor=0x002859ff
    unfocused_opacity=1.0
    focused_opacity=1.0
    default_mfact=0.6
    new_is_master=1
    gappih=0
    gappiv=0
    gappoh=0
    gappov=0
    # fullscreen tearing for games (0=off, 1=any window, 2=fullscreen only)
    allow_tearing=2
    animations=1
    animation_type_open=slide
    animation_type_close=slide
    animation_fade_in=1
    animation_fade_out=1
    tag_animation_direction=1

    # --- Layout per tag — scroller everywhere (mango's scroll layout) ---
    tagrule=id:1, layout_name:scroller
    tagrule=id:2, layout_name:scroller
    tagrule=id:3, layout_name:scroller
    tagrule=id:4, layout_name:scroller
    tagrule=id:5, layout_name:scroller
    tagrule=id:7, layout_name:scroller
    tagrule=id:8, layout_name:scroller
    tagrule=id:9, layout_name:scroller
    tagrule=id:11, layout_name:scroller
    tagrule=id:12, layout_name:scroller
    tagrule=id:13, layout_name:scroller
    tagrule=id:14, layout_name:scroller
    tagrule=id:15, layout_name:scroller
    tagrule=id:16, layout_name:scroller
    tagrule=id:17, layout_name:scroller
    tagrule=id:18, layout_name:scroller
    tagrule=id:19, layout_name:scroller
    tagrule=id:20, layout_name:scroller
    tagrule=id:21, layout_name:scroller
    tagrule=id:22, layout_name:scroller

    # --- Class routing (hyprland workspace routing) ---
    windowrule=appid:^term$,tags:1
    windowrule=appid:^([Vv]ivaldi-stable|[Vv]ivaldi)$,tags:2
    windowrule=appid:^nwim$,tags:3
    windowrule=appid:^(steam|Steam)$,tags:4
    windowrule=appid:^sioyek$,tags:5
    windowrule=appid:^mpv$,tags:7
    windowrule=appid:^obs$,tags:8
    windowrule=appid:^swayimg$,tags:9
    windowrule=appid:^(.virt-manager-wrapped|qemu-system-x86_64)$,tags:11
    windowrule=appid:^(com.usebottles.bottles)$,tags:12
    windowrule=appid:^(zestbay|Carla2)$,tags:13
    windowrule=appid:^Renoise$,tags:14
    windowrule=appid:^Vital$,tags:21
    windowrule=title:^(VCV Rack).*,tags:22
    windowrule=appid:^(org.nicotine_plus.Nicotine)$,tags:15
    windowrule=appid:^(Bazecor|Vial|via)$,tags:16
    windowrule=appid:^(im.riot.Riot)$,tags:17
    windowrule=appid:^(Vmware-view|xfreerdp|remmina|org.remmina.Remmina)$,tags:18
    windowrule=appid:^(Obsidian)$,tags:19
    windowrule=appid:^(winboat|WinBoat)$,tags:20

    # --- Float rules ---
    windowrule=tags:4, isfloating:1
    windowrule=appid:^swayimg$,isfloating:1
    windowrule=title:^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|File Upload),isfloating:1
    windowrule=title:^.*Picture-in-Picture.*,isfloating:1
    windowrule=appid:^(org.gnome.Calculator)$,isfloating:1

    # --- Named scratchpads (window marked hidden; bind toggles / spawns) ---
    windowrule=appid:^org\.telegram\.desktop$,isnamedscratchpad:1
    windowrule=appid:^music$,isnamedscratchpad:1
    windowrule=appid:^mixer$,isnamedscratchpad:1
    windowrule=appid:^torrment$,isnamedscratchpad:1
    windowrule=appid:^vpn$,isnamedscratchpad:1
    windowrule=appid:^rebuild$,isnamedscratchpad:1
    windowrule=appid:^teardown$,isnamedscratchpad:1

    # --- Keybinds (M4=SUPER, M1=ALT, C=CTRL, SH=SHIFT) ---
    bind=SUPER,Return,spawn,kitty --single-instance --class term
    bind=SUPER,Escape,killclient,
    bind=SUPER,r,togglefullscreen,
    bind=SUPER,h,focusdir,left
    bind=SUPER,j,focusdir,down
    bind=SUPER,k,focusdir,up
    bind=SUPER,l,focusdir,right
    bind=SUPER,Tab,focusstack,next
    bind=SUPER,n,switch_layout
    bind=SUPER,S,switch_keyboard_layout
    bind=SUPER,o,toggleoverview
    bind=SUPER,c,spawn,vicinae deeplink vicinae://launch/clipboard/history
    bind=SUPER+CTRL,r,spawn,quickshell-restart
    # keybinds above stay alphabetical-ish; quickshell-restart = panel restart

    # apps (hyprland raise->launch becomes plain spawn; no run-or-raise in mango yet)
    bind=SUPER,w,spawn,vivaldi
    bind=SUPER,x,spawn,kitty --class term
    bind=SUPER,q,spawn,kitty --class nwim -e /home/neg/.local/bin/v
    bind=SUPER,b,spawn,~/.local/bin/pl video
    bind=SUPER+CTRL,c,spawn,swayimg ~/dw
    bind=SUPER+SHIFT,c,spawn,wl random ~/pic/wl
    bind=SUPER,g,spawn,steam
    bind=SUPER+CTRL,o,spawn,obs
    bind=SUPER+CTRL,n,spawn,obsidian
    bind=SUPER+CTRL,v,spawn,bazecor

    # workspaces (tags)
    bind=SUPER,1,view,1,0
    bind=SUPER,2,view,2,0
    bind=SUPER,3,view,3,0
    bind=SUPER,4,view,4,0
    bind=SUPER,5,view,5,0
    bind=SUPER,7,view,7,0
    bind=SUPER,8,view,8,0
    bind=SUPER,9,view,9,0
    bind=SUPER+SHIFT,1,tag,1,0
    bind=SUPER+SHIFT,2,tag,2,0
    bind=SUPER+SHIFT,3,tag,3,0
    bind=SUPER+SHIFT,4,tag,4,0
    bind=SUPER+SHIFT,5,tag,5,0
    bind=SUPER+SHIFT,7,tag,7,0
    bind=SUPER+SHIFT,8,tag,8,0
    bind=SUPER+SHIFT,9,tag,9,0
    bind=SUPER,Left,viewtoleft,0
    bind=SUPER,Right,viewtoright,0
    bind=ALT,Tab,viewtoleft,0
    axisbind=SUPER,UP,viewtoleft_have_client
    axisbind=SUPER,DOWN,viewtoright_have_client
    mousebind=SUPER,btn_left,moveresize,curmove
    mousebind=SUPER,btn_right,moveresize,curresize

    # scratchpads ("none" = no title match; last arg = spawn if not running)
    bind=SUPER,e,toggle_named_scratchpad,^org\.telegram\.desktop$,none
    bind=SUPER,f,toggle_named_scratchpad,^music$,none,kitty --class music -e rmpc
    bind=SUPER+CTRL,p,toggle_named_scratchpad,^mixer$,none,kitty --class mixer -e ncpamixer
    bind=SUPER,t,toggle_named_scratchpad,^torrment$,none,kitty --class torrment -e rustmission
    bind=SUPER,u,toggle_named_scratchpad,^vpn$,none,kitty --class vpn -e tun status
    bind=SUPER+SHIFT,n,toggle_named_scratchpad,^rebuild$,none,kitty --class rebuild -e nh os switch /etc/nixos#odin --option substitute false
    bind=SUPER,d,toggle_named_scratchpad,^teardown$,none,kitty --class teardown -e btop

    # media keys
    bind=NONE,XF86AudioNext,spawn,genlc-media up; swayosd-client --output-volume +5
    bind=NONE,XF86AudioPrev,spawn,genlc-media down; swayosd-client --output-volume -5
    bind=NONE,XF86AudioMute,spawn,genlc-media mute; swayosd-client --output-volume mute-toggle
    bind=NONE,XF86AudioRaiseVolume,spawn,swayosd-client --output-volume +5; genlc-media up
    bind=NONE,XF86AudioLowerVolume,spawn,swayosd-client --output-volume -5; genlc-media down
    bind=NONE,XF86AudioPause,spawn,playerctl play-pause
    bind=NONE,XF86MonBrightnessUp,spawn,swayosd-client --brightness +10
    bind=NONE,XF86MonBrightnessDown,spawn,swayosd-client --brightness -10

    # resize keymode (SUPER+CTRL+backslash enters, Escape leaves)
    bind=SUPER+CTRL,backslash,setkeymode,resize
    keymode=resize
    bind=NONE,Left,resizewin,-10,0
    bind=NONE,Right,resizewin,10,0
    bind=NONE,Up,resizewin,0,-10
    bind=NONE,Down,resizewin,0,10
    bind=NONE,Escape,setkeymode,default
    keymode=default
  '';

  # ru-layout daemon for MangoWM — mirrors modules/user/nix-maid/hyprland/ru-layout.nix
  # (us in hotkey-heavy classes, ru elsewhere) but drives the mango IPC socket:
  # `get focusing-client` for the focused appid, `dispatch switch_keyboard_layout,<idx>`
  # to set the XKB group. Indexes are 1-based for mango (0 means "cycle").
  ruHotkeys = config.features.input.ruHotkeys or { };
  ruHotkeysEnabled = ruHotkeys.enable or false;
  usClasses = lib.concatStringsSep " " (ruHotkeys.usClasses or [ ]);
  ruUsIdx = toString ((ruHotkeys.usLayoutIndex or 0) + 1);
  ruRuIdx = toString ((ruHotkeys.ruLayoutIndex or 1) + 1);
  ruPollSec = ruHotkeys.pollSec or "0.5";

  ruLayoutDaemon = pkgs.writeShellScript "mango-ru-layout-daemon" ''
    # Per-window keyboard layout switching for MangoWM (mirror of
    # modules/user/nix-maid/hyprland/ru-layout.nix, driven via the mango IPC
    # socket instead of hyprctl). us for hotkey-heavy classes, ru otherwise.
    set -u

    socat_bin='${lib.getExe pkgs.socat}'
    sed_bin='${lib.getExe pkgs.gnused}'
    sleep_bin='${lib.getExe' pkgs.coreutils "sleep"}'
    head_bin='${lib.getExe' pkgs.coreutils "head"}'

    us_classes='${usClasses}'
    us_idx='${ruUsIdx}'
    ru_idx='${ruRuIdx}'
    poll_sec='${ruPollSec}'

    # Socket: mango exports MANGO_INSTANCE_SIGNATURE, but systemd user services
    # do not inherit it, so fall back to the glob in $XDG_RUNTIME_DIR.
    sock="''\${MANGO_INSTANCE_SIGNATURE:-}"
    if [ -z "$sock" ] || [ ! -S "$sock" ]; then
      sock="$(ls -1 "''\${XDG_RUNTIME_DIR:-/run/user/1000}"/mango-*.sock 2>/dev/null | "$head_bin" -1)"
    fi
    if [ -z "$sock" ]; then
      echo "mango IPC socket not found" >&2
      exit 1
    fi

    send() {
      printf '%s\n' "$1" | "$socat_bin" - UNIX-CONNECT:"$sock" 2>/dev/null
    }

    # `get focusing-client` JSON has "appid":"term" or "appid":null (and an
    # error object when nothing is focused) — extract the quoted appid, else empty.
    focused_appid() {
      send "get focusing-client" | "$sed_bin" -n 's/.*"appid":"\([^"]*\)".*/\1/p'
    }

    current=""
    while :; do
      appid="$(focused_appid)"
      if [ "$appid" != "$current" ]; then
        current="$appid"
        case " $us_classes " in
          *" $appid "*) idx="$us_idx" ;;
          *) idx="$ru_idx" ;;
        esac
        send "dispatch switch_keyboard_layout,$idx" >/dev/null || true
      fi
      "$sleep_bin" "$poll_sec"
    done
  '';

  # start-mango: mango session launcher (mirrors the repo's hypr-start flow:
  # import env into the user session, start the session target, exec mango).
  startMango = pkgs.writeShellScriptBin "start-mango" ''
    set -euo pipefail
    LOG="/tmp/mango-start.log"
    echo "Starting mango at $(date)" > "$LOG"
    sleep 1
    echo "Importing environment..." >> "$LOG"
    dbus-update-activation-environment --systemd --all
    systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE QT_XDG_DESKTOP_PORTAL QT_STYLE_OVERRIDE QT_QPA_PLATFORMTHEME
    systemctl --user start mango-session.target
    # Pin the dGPU for wlroots: WLR_DRM_DEVICES is a colon-separated device
    # list, so the by-path name (pci-0000:03:00.0-card contains colons) cannot
    # be used as-is — wlroots would split it and find no GPU. Resolve it to
    # the plain /dev/dri/cardN node.
    if drmDev="$(readlink -f /dev/dri/by-path/pci-0000:03:00.0-card 2>/dev/null)"; then
      export WLR_DRM_DEVICES="$drmDev"
    fi
    # greetd starts the session on the same VT the greeter used, so the kernel
    # never switches VTs and logind leaves the session inactive. wlroots aborts
    # unless the session becomes active within 10s ("Timeout waiting session to
    # become active"). Force a VT round-trip via logind (Seat.SwitchTo is
    # allowed for local sessions without auth) so logind observes a console
    # change and marks our session active.
    vt="''${XDG_VTNR:-1}"
    other=$([ "$vt" = 1 ] && echo 3 || echo 1)
    if [ -n "''${XDG_SESSION_ID:-}" ]; then
      for _ in 1 2 3 4 5; do
        [ "$(/run/current-system/sw/bin/loginctl show-session "$XDG_SESSION_ID" -p Active --value 2>/dev/null)" = "yes" ] && break
        /run/current-system/sw/bin/busctl --system call org.freedesktop.login1 /org/freedesktop/login1/seat/seat0 org.freedesktop.login1.Seat SwitchTo u "$other" 2>/dev/null || true
        /run/current-system/sw/bin/busctl --system call org.freedesktop.login1 /org/freedesktop/login1/seat/seat0 org.freedesktop.login1.Seat SwitchTo u "$vt" 2>/dev/null || true
        sleep 0.5
      done
    fi
    echo "Executing mango..." >> "$LOG"
    exec mango "$@"
  '';
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui" && cfg.enable) (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.mango # MangoWM compositor (wl-only branch)
          startMango # mango session launcher (env import + session target)
          pkgs.swayidle # idle daemon (locks via swaylock after 2 min)
          pkgs.swaylock # lock screen for the mango session
        ];

        # Mango session target — mirrors hyprland-session.target so user
        # services (quickshell-mango, swayidle, ...) start/stop with the session.
        systemd.user.targets.mango-session = {
          unitConfig = {
            Description = "MangoWM compositor session";
            Documentation = [ "man:systemd.special(7)" ];
            BindsTo = [ "graphical-session.target" ];
            Wants = [ "graphical-session-pre.target" ];
            After = [ "graphical-session-pre.target" ];
          };
        };

        systemd.user.services = {
          swayidle = {
            description = "MangoWM idle daemon (swayidle -> swaylock)";
            wantedBy = [ "mango-session.target" ];
            bindsTo = [ "mango-session.target" ];
            after = [ "mango-session.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 120 '${pkgs.swaylock}/bin/swaylock -f'";
              Restart = "on-failure";
              RestartSec = "2";
            };
          };
          swaylock-sleep = {
            description = "Lock screen before sleep";
            before = [ "sleep.target" ];
            wantedBy = [ "sleep.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.swaylock}/bin/swaylock -f";
            };
          };
          quickshell-mango = {
            description = "Quickshell panel for MangoWM";
            wantedBy = [ "mango-session.target" ];
            bindsTo = [ "mango-session.target" ];
            after = [ "mango-session.target" ];
            serviceConfig = {
              ExecStart = "/run/current-system/sw/bin/quickshell -p %h/.config/quickshell/shell.qml";
              Environment = [ "QS_SESSION=mango" ];
              Restart = "on-failure";
              RestartSec = "5";
            };
          };
          # ru-layout-mango: per-window keyboard layout (us in hotkey-heavy
          # apps, ru elsewhere) — mango IPC port of hyprland/ru-layout.nix,
          # gated by the same features.input.ruHotkeys flag as the Hyprland one.
          ru-layout-mango = lib.mkIf ruHotkeysEnabled {
            description = "Per-window keyboard layout switching (us in hotkey-heavy apps)";
            wantedBy = [ "mango-session.target" ];
            bindsTo = [ "mango-session.target" ];
            after = [ "mango-session.target" ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${ruLayoutDaemon}";
              Restart = "on-failure";
              RestartSec = "2";
            };
          };
        };
      }
      (neg.mkHomeFiles {
        ".config/mango/config.conf".text = configConf;
        ".config/swaylock/config".text = ''
          color=000000
          ring-color=ffffff
          inside-color=000000
          key-hl-color=006FCC
          bs-hl-color=FF6B81
          line-color=00000000
          separator-color=00000000
          font=Iosevka
          indicator-caps-lock
        '';
      })
    ]
  );
}
