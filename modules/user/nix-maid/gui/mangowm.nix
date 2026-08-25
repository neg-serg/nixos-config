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
    monitorrule=name:DP-2, width:3840, height:2160, refresh:240, scale:2, vrr:1, x:0, y:0
    monitorrule=name:DP-1, disable:1
    # ICC: Display P3 (panel is 100% DCI-P3) — profile deployed to ~/.config/mango/Display-P3.icc
    monitorrule=name:DP-2, icc:/home/${config.users.main.name or "neg"}/.config/mango/Display-P3.icc

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
    tagrule=id:6, layout_name:scroller
    tagrule=id:7, layout_name:scroller
    tagrule=id:8, layout_name:scroller
    tagrule=id:9, layout_name:scroller
    tagrule=id:10, layout_name:scroller
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

    # --- Class routing (hyprland workspace routing) ---
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
    windowrule=appid:^(org.nicotine_plus.Nicotine)$,tags:15
    windowrule=appid:^(Bazecor|Vial|via)$,tags:16
    windowrule=appid:^(im.riot.Riot)$,tags:17
    windowrule=appid:^(Obsidian)$,tags:19

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
    bind=SUPER,6,view,6,0
    bind=SUPER,7,view,7,0
    bind=SUPER,8,view,8,0
    bind=SUPER,9,view,9,0
    bind=SUPER+SHIFT,1,tag,1,0
    bind=SUPER+SHIFT,2,tag,2,0
    bind=SUPER+SHIFT,3,tag,3,0
    bind=SUPER+SHIFT,4,tag,4,0
    bind=SUPER+SHIFT,5,tag,5,0
    bind=SUPER+SHIFT,6,tag,6,0
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
          pkgs.waybar # status bar for the mango session
        ];

        # Mango session target — mirrors hyprland-session.target so user
        # services (waybar, swayidle, ...) start/stop with the session.
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
          waybar = {
            description = "Waybar status bar for MangoWM";
            wantedBy = [ "mango-session.target" ];
            bindsTo = [ "mango-session.target" ];
            after = [ "mango-session.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.waybar}/bin/waybar";
              Restart = "on-failure";
              RestartSec = "2";
            };
          };
        };
      }
      (neg.mkHomeFiles {
        ".config/mango/config.conf".text = configConf;
        ".config/mango/Display-P3.icc".source = config.lib.neg.path "files/gui/mango/Display-P3.icc";
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
        ".config/waybar/config".text = ''
          {
            "layer": "top",
            "height": 28,
            "spacing": 8,
            "modules-left": ["wlr/workspaces"],
            "modules-center": ["clock"],
            "modules-right": ["pulseaudio", "backlight", "network", "cpu", "memory", "tray"],
            "wlr/workspaces": {
              "format": "{name}",
              "on-click": "activate"
            },
            "clock": { "format": "{:%H:%M}", "tooltip-format": "{:%a %d %b %Y}" },
            "pulseaudio": { "format": "{volume}%", "on-click": "swayosd-client --output-volume mute-toggle" },
            "backlight": { "format": "{percent}%" },
            "network": { "format-wifi": "{essid}", "format-ethernet": "eth" },
            "cpu": { "format": "CPU {usage}%" },
            "memory": { "format": "RAM {}%" },
            "tray": { "spacing": 6 }
          }
        '';
        ".config/waybar/style.css".text = ''
          * { font-family: Iosevka; font-size: 12px; }
          window#waybar { background: rgba(24, 28, 37, 0.95); color: #CBD6E5; }
          #workspaces button { color: #CBD6E5; background: transparent; border-radius: 4px; padding: 0 6px; }
          #workspaces button.active { color: #181C25; background: #006FCC; }
          #clock, #pulseaudio, #backlight, #network, #cpu, #memory, #tray { padding: 0 8px; }
          #clock { font-weight: bold; }
        '';
      })
    ]
  );
}
