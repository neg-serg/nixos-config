{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.gui.sway;
  mainUser = config.users.main.name or "neg";
  # Ported from MangoWM (modules/user/nix-maid/gui/mangowm.nix), which itself
  # mirrors files/gui/hypr/hyprland.lua. Plain-sway-safe (no swayfx-only keys).
  swayConfig = ''
    # --- Monitor: DP-2 3840x2160@240 scale 2 VRR 10-bit; DP-1 disabled ---
    output DP-2 {
      # Preferred mode is 3840x2160@239.99Hz; explicit @240Hz does not match and
      # drops the whole output config ("Could not find config for output DP-2").
      mode 3840x2160
      scale 2
      adaptive_sync on
      render_bit_depth 10
      # Display P3 ICC (D65, DCI-P3 primaries, sRGB transfer); needs the Vulkan
      # renderer (start-sway sets WLR_RENDERER=vulkan); conflicts with hdr on.
      color_profile icc /home/${mainUser}/.config/sway/Display-P3.icc
    }
    output DP-1 disable
    # Wallpaper (swaybg reads this; change with: swaymsg output * bg <path> fill)
    output * bg /home/${mainUser}/pic/wl/wallhaven-exjgj8.png fill
    # HDR (sway 1.12, experimental, needs WLR_RENDERER=vulkan + monitor HDR mode on):
    # output DP-2 hdr on

    # --- Input ---
    input type:keyboard {
      xkb_layout us,ru
      repeat_rate 35
      repeat_delay 250
    }
    input type:touchpad {
      natural_scroll enabled
      tap enabled
    }

    # --- General ---
    set $mod Mod4
    font pango:Iosevka 10
    gaps inner 0
    gaps outer 0
    client.focused           #002859 #002859 #ffffff #002859 #002859
    client.focused_inactive  #002859 #002859 #888888 #002859 #002859
    client.unfocused         #002859 #002859 #888888 #002859 #002859
    client.urgent            #2f9e44 #2f9e44 #ffffff #2f9e44 #2f9e44
    default_border pixel 1

    # Session target starts from sway's exec (compositor already up), mirroring
    # the mango fix for service races.
    exec systemctl --user start sway-session.target

    # --- Floating rules ---
    for_window [app_id="swayimg"] floating enable
    for_window [title="Picture-in-Picture"] floating enable
    for_window [app_id="org.gnome.Calculator"] floating enable
    for_window [title="^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|File Upload)"] floating enable

    # --- Scratchpad classes (toggled by sway-scratch) ---
    for_window [app_id="^music$"] move scratchpad
    for_window [app_id="^mixer$"] move scratchpad
    for_window [app_id="^torrment$"] move scratchpad
    for_window [app_id="^vpn$"] move scratchpad
    for_window [app_id="^rebuild$"] move scratchpad
    for_window [app_id="^teardown$"] move scratchpad

    # --- Layout switch: SUPER+S (same key as Hyprland/Mango) ---
    # --no-repeat: holding $mod+s (>=250ms, repeat delay) would toggle the layout
    # multiple times and end up back on the same layout (intermittent 'no switch').
    bindsym --to-code --no-repeat Mod4+s exec swaymsg input type:keyboard xkb_switch_layout next

    # --- Window management ---
    bindsym $mod+Return exec sway-run-or-raise '^term$' kitty --single-instance --class term
    bindsym $mod+Escape kill
    bindsym --to-code Mod4+r fullscreen toggle
    bindsym --to-code Mod4+h focus left
    bindsym --to-code Mod4+j focus down
    bindsym --to-code Mod4+k focus up
    bindsym --to-code Mod4+l focus right
    bindsym $mod+Tab focus next
    bindsym --to-code Mod4+Shift+h move left
    bindsym --to-code Mod4+Shift+j move down
    bindsym --to-code Mod4+Shift+k move up
    bindsym --to-code Mod4+Shift+l move right
    bindsym Mod1+Tab workspace prev
    bindsym $mod+button4 workspace prev
    bindsym $mod+button5 workspace next
    bindsym $mod+Left workspace prev
    bindsym $mod+Right workspace next
    bindsym $mod+Ctrl+Left move container to workspace prev
    bindsym $mod+Ctrl+Right move container to workspace next

    # --- Apps (run-or-raise) ---
    bindsym --to-code Mod4+w exec sway-run-or-raise '^([Vv]ivaldi-stable|[Vv]ivaldi)$' vivaldi
    bindsym --to-code Mod4+x exec sway-run-or-raise '^term$' kitty --class term
    bindsym --to-code Mod4+q exec sway-run-or-raise '^nwim$' kitty --class nwim -e /home/${mainUser}/.local/bin/v
    bindsym --to-code Mod4+b exec sway-run-or-raise '^mpv$' ~/.local/bin/pl video
    bindsym --to-code Mod4+Ctrl+c exec sway-run-or-raise '^swayimg$' swayimg ~/dw
    bindsym --to-code Mod4+Shift+c exec wl random ~/pic/wl
    bindsym --to-code Mod4+g exec sway-run-or-raise '^(steam|com\.valvesoftware\.Steam|steam_app.*|gamescope)$' steam
    bindsym --to-code Mod4+Ctrl+o exec sway-run-or-raise '^(obs|com\.obsproject\.Studio)$' obs
    bindsym --to-code Mod4+Ctrl+n exec sway-run-or-raise '^(Obsidian|md\.obsidian\.Obsidian)$' obsidian
    bindsym --to-code Mod4+Ctrl+v exec sway-run-or-raise '^[Bb]azecor$' bazecor
    bindsym --to-code Mod4+c exec vicinae deeplink vicinae://launch/clipboard/history

    # --- Workspaces ---
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9
    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9

    # --- Scratchpads ---
    bindsym --to-code Mod4+e exec sway-scratch '^org\.telegram\.desktop$' telegram-desktop
    bindsym --to-code Mod4+f exec sway-scratch '^music$' kitty --class music -e rmpc
    bindsym --to-code Mod4+Ctrl+p exec sway-scratch '^mixer$' kitty --class mixer -e ncpamixer
    bindsym --to-code Mod4+t exec sway-scratch '^torrment$' kitty --class torrment -e rustmission
    bindsym --to-code Mod4+u exec sway-scratch '^vpn$' kitty --class vpn -e tun status
    bindsym --to-code Mod4+Shift+n exec sway-scratch '^rebuild$' kitty --class rebuild -e nh os switch /etc/nixos#odin --option substitute false
    bindsym --to-code Mod4+d exec sway-scratch '^teardown$' kitty --class teardown -e btop

    # --- Media keys ---
    bindsym XF86AudioNext exec 'genlc-media up; swayosd-client --output-volume +5'
    bindsym XF86AudioPrev exec 'genlc-media down; swayosd-client --output-volume -5'
    bindsym XF86AudioMute exec 'genlc-media mute; swayosd-client --output-volume mute-toggle'
    bindsym XF86AudioRaiseVolume exec 'swayosd-client --output-volume +5; genlc-media up'
    bindsym XF86AudioLowerVolume exec 'swayosd-client --output-volume -5; genlc-media down'
    bindsym XF86AudioPause exec playerctl play-pause
    bindsym XF86AudioMicMute exec swayosd-client --input-volume mute-toggle
    bindsym XF86MonBrightnessUp exec swayosd-client --brightness +10
    bindsym XF86MonBrightnessDown exec swayosd-client --brightness -10
    bindsym --to-code Mod4+Shift+w exec ~/.local/bin/pl cmd play-pause
    bindsym --to-code Mod4+comma exec ~/.local/bin/pl cmd previous
    bindsym --to-code Mod4+period exec ~/.local/bin/pl cmd next
    bindsym --to-code Mod4+Shift+i exec ~/.local/bin/pl vol mute
    bindsym --to-code Mod4+Shift+o exec ~/.local/bin/pl vol unmute
    bindsym --to-code Mod4+m exec ~/.local/bin/music-rename current

    # --- Ported from Hyprland (binds that were missing in the sway port) ---
    # Workspace prev on M4+slash (hyprland had both M1+Tab and M4+slash).
    bindsym --to-code Mod4+slash workspace prev
    # Password/OTP picker from the pass store (vicinae dmenu).
    bindsym --to-code Mod4+p exec pass-2col
    # Screen recording (wlroots-specific screenrec helper).
    bindsym --to-code Mod4+Shift+v exec ~/.local/bin/screenrec screen
    bindsym --to-code Mod4+Shift+Ctrl+v exec ~/.local/bin/screenrec area
    # Music synths (VSTPlugin in SC via local-bin/synth). M4+Shift+l is move
    # right in sway (i3 convention), so LegendHZ moved to M4+Shift+Ctrl+l.
    bindsym --to-code Mod4+Shift+s exec synth Surge_XT
    bindsym --to-code Mod4+Shift+Ctrl+l exec synth LegendHZ
    bindsym --to-code Mod4+Shift+t exec sc-live # raw SuperCollider live-coding scene (scnvim)
    # vicinae command menu (app launcher, Alt+q like hyprland).
    bindsym Mod1+q exec vicinae toggle
    # vicinae window switcher (Alt+g).
    bindsym Mod1+g exec vicinae deeplink vicinae://launch/wm/switch-windows
    # vicinae-driven helper menu (music/clipboard/network actions).
    bindsym --to-code Mod4+Shift+m exec ~/.local/bin/main-menu

    # --- Floating windows (i3-style; was mouse-drag binds in hyprland) ---
    # M4+drag moves/resizes floating windows; M4+space toggles floating.
    floating_modifier $mod normal
    bindsym --to-code Mod4+space floating toggle
    bindsym --to-code Mod4+v layout toggle split

    # --- Lock (reset to us first, like Hyprland) ---
    # Lock: $mod+Shift+l is taken by "move right", so use $mod+Shift+Escape.
    bindsym --no-repeat $mod+Shift+Escape exec 'swaymsg input type:keyboard xkb_switch_layout 0; swaylock -f'

    # --- Screenshots ---
    bindsym $mod+Shift+r exec 'shot="$HOME/pic/shots/satty-$(date +%Y%m%d-%H.%M.%S).png"; grim -l 0 "$shot" && pic-info "$shot"'
    bindsym $mod+Shift+Ctrl+r exec 'shot="$HOME/pic/shots/satty-$(date +%Y%m%d-%H.%M.%S).png"; grim -l 0 -g "$(slurp)" "$shot" && pic-info "$shot"'

    # --- Resize mode ---
    mode "resize" {
      bindsym Left         resize shrink width 10px
      bindsym Right        resize grow width 10px
      bindsym Up           resize shrink height 10px
      bindsym Down         resize grow height 10px
      bindsym --to-code h resize shrink width 10px
      bindsym --to-code l resize grow width 10px
      bindsym --to-code k resize shrink height 10px
      bindsym --to-code j resize grow height 10px
      bindsym Shift+Left   resize grow width 10px
      bindsym Shift+Right  resize shrink width 10px
      bindsym Shift+Up     resize grow height 10px
      bindsym Shift+Down   resize shrink height 10px
      bindsym Return       mode "default"
      bindsym Escape       mode "default"
    }
    bindsym --to-code Mod4+Ctrl+backslash mode "resize"
  '';

  # SwayFX: same config + eye candy (blur/corners/shadows).
  swayfxConfig = ''
    include ~/.config/sway/config
    blur enable
    blur_xray enable
    blur_radius 10
    corner_radius 8
    shadows enable
    shadow_blur_radius 14
  '';

  # sway session launcher: import env, pin vulkan renderer, exec sway.
  startSway = pkgs.writeShellScriptBin "start-sway" ''
    set -euo pipefail
    LOG="/tmp/sway-start.log"
    echo "Starting sway at $(date)" > "$LOG"
    dbus-update-activation-environment --systemd --all
    systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE QT_XDG_DESKTOP_PORTAL
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    # 10-bit/HDR path on AMD: only the vulkan renderer has output_color_transform.
    export WLR_RENDERER=vulkan
    export XDG_CURRENT_DESKTOP=sway
    exec ${lib.getExe pkgs.sway} "$@"
  '';

  startSwayfx = pkgs.writeShellScriptBin "start-swayfx" ''
    set -euo pipefail
    LOG="/tmp/swayfx-start.log"
    echo "Starting swayfx at $(date)" > "$LOG"
    dbus-update-activation-environment --systemd --all
    systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE QT_XDG_DESKTOP_PORTAL
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    export WLR_RENDERER=vulkan
    export XDG_CURRENT_DESKTOP=swayfx
    exec ${lib.getExe pkgs.swayfx} -c /home/${mainUser}/.config/swayfx/config "$@"
  '';

  # sway-run-or-raise: focus an existing window by app_id/class regex, else launch.
  swayRunOrRaise = pkgs.writeShellScriptBin "sway-run-or-raise" ''
    set -eu
    [ $# -ge 2 ] || { echo "usage: sway-run-or-raise <class-regex> <launch...>" >&2; exit 1; }
    cls="$1"; shift
    jq_bin='${lib.getExe pkgs.jq}'
    swaymsg_bin='${lib.getExe' pkgs.sway "swaymsg"}'
    id="$("$swaymsg_bin" -t get_tree 2>/dev/null | "$jq_bin" -r --arg cls "$cls" '
      [.. | objects | select((.app_id? // .class?) != null and ((.app_id? // .class?) | test($cls; "i"))) | .id][0] // empty
    ' 2>/dev/null || true)"
    if [ -n "$id" ]; then
      "$swaymsg_bin" "[con_id=$id]" focus >/dev/null 2>&1 || true
    else
      nohup "$@" >/dev/null 2>&1 &
    fi
  '';

  # sway-scratch: toggle a scratchpad window by app_id/class; spawn if absent.
  swayScratch = pkgs.writeShellScriptBin "sway-scratch" ''
    set -eu
    [ $# -ge 2 ] || { echo "usage: sway-scratch <app-id-regex> <launch...>" >&2; exit 1; }
    cls="$1"; shift
    jq_bin='${lib.getExe pkgs.jq}'
    swaymsg_bin='${lib.getExe' pkgs.sway "swaymsg"}'
    focused="$("$swaymsg_bin" -t get_tree 2>/dev/null | "$jq_bin" -r --arg cls "$cls" '
      .. | objects | select(.focused == true) | ((.app_id? // .class?) | test($cls; "i"))
    ' | head -1)"
    if [ "$focused" = "true" ]; then
      "$swaymsg_bin" move scratchpad >/dev/null 2>&1 || true
    else
      n="$("$swaymsg_bin" -t get_tree 2>/dev/null | "$jq_bin" -r --arg cls "$cls" '
        [.. | objects | select((.app_id? // .class?) != null and ((.app_id? // .class?) | test($cls; "i")))] | length
      ' 2>/dev/null || echo 0)"
      if [ "$n" -gt 0 ]; then
        "$swaymsg_bin" "[app_id=\"$cls\"]" scratchpad show >/dev/null 2>&1 || true
      else
        nohup "$@" >/dev/null 2>&1 &
      fi
    fi
  '';

  # sway-ru-layout: per-window keyboard layout (us in hotkey-heavy classes, ru
  # otherwise) — swaymsg port of hyprland/ru-layout.nix, same ruHotkeys flag.
  ruHotkeys = config.features.input.ruHotkeys or { };
  ruHotkeysEnabled = ruHotkeys.enable or false;
  usClasses = lib.concatStringsSep " " (ruHotkeys.usClasses or [ ]);
  ruUsIdx = toString (ruHotkeys.usLayoutIndex or 0);
  ruRuIdx = toString (ruHotkeys.ruLayoutIndex or 1);
  ruPollSec = ruHotkeys.pollSec or "0.5";

  swayRuLayout = pkgs.writeShellScript "sway-ru-layout-daemon" ''
    set -u
    jq_bin='${lib.getExe pkgs.jq}'
    swaymsg_bin='${lib.getExe' pkgs.sway "swaymsg"}'
    sleep_bin='${lib.getExe' pkgs.coreutils "sleep"}'
    us_classes='${usClasses}'
    us_idx='${ruUsIdx}'
    ru_idx='${ruRuIdx}'
    poll_sec='${ruPollSec}'
    current=""
    while :; do
      appid="$("$swaymsg_bin" -t get_tree 2>/dev/null | "$jq_bin" -r '.. | objects | select(.focused == true) | (.app_id? // .class? // "")' | head -1)"
      if [ "$appid" != "$current" ]; then
        current="$appid"
        case " $us_classes " in
          *" $appid "*) idx="$us_idx" ;;
          *) idx="$ru_idx" ;;
        esac
        "$swaymsg_bin" input type:keyboard xkb_switch_layout "$idx" 2>/dev/null || true
      fi
      "$sleep_bin" "$poll_sec"
    done
  '';

  swayDesktop = pkgs.writeTextDir "share/wayland-sessions/sway.desktop" ''
    [Desktop Entry]
    Name=sway
    Comment=sway Wayland compositor
    Exec=start-sway
    Type=Application
  '';
  swayfxDesktop = pkgs.writeTextDir "share/wayland-sessions/swayfx.desktop" ''
    [Desktop Entry]
    Name=SwayFX
    Comment=Sway with eye candy
    Exec=start-swayfx
    Type=Application
  '';
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui" && cfg.enable) (
    lib.mkMerge [
      {
        # Vulkan renderer system-wide: wlroots only applies color_profile icc
        # (and 10-bit/HDR) with WLR_RENDERER=vulkan, so every way to start a
        # session (greeter entry, TTY, user service) gets it. /etc/environment
        # reaches PAM/greetd; sessionVariables covers login shells.
        environment.variables.WLR_RENDERER = "vulkan";
        environment.sessionVariables.WLR_RENDERER = "vulkan";

        environment.systemPackages = [
          pkgs.sway # Sway 1.12 Wayland compositor (wlroots, 10-bit/HDR capable)
          pkgs.swayfx # SwayFX — sway fork with blur/corners/shadows
          startSway # sway session launcher (env import + vulkan renderer)
          startSwayfx # swayfx session launcher
          swayRunOrRaise # run-or-raise for app binds (focus by app_id, else launch)
          swayScratch # scratchpad toggle helper
          (lib.hiPrio swayDesktop) # greeter entry; wins over the sway package's own
          # wayland-sessions/sway.desktop (Exec=sway) so the greeter starts the
          # vulkan launcher (start-sway) — required for color_profile icc.
          (lib.hiPrio swayfxDesktop) # greeter session entry
          pkgs.swayidle # idle daemon (locks via swaylock after 2 min)
          pkgs.swaylock # lock screen for the sway session
        ];

        # Sway session target — user services (swayidle, sway-ru-layout, wl-daemon)
        # start/stop with the session; started from sway's exec (config above).
        systemd.user.targets.sway-session = {
          unitConfig = {
            Description = "Sway compositor session";
            BindsTo = [ "graphical-session.target" ];
            Wants = [ "graphical-session-pre.target" ];
            After = [ "graphical-session-pre.target" ];
          };
        };

        systemd.user.services = {
          swayidle = {
            description = "Sway idle daemon (swayidle -> swaylock)";
            wantedBy = [ "sway-session.target" ];
            bindsTo = [ "sway-session.target" ];
            after = [ "sway-session.target" ];
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
          # Per-window keyboard layout (us in hotkey-heavy apps, ru elsewhere).
          sway-ru-layout = lib.mkIf ruHotkeysEnabled {
            description = "Per-window keyboard layout switching (us in hotkey-heavy apps)";
            wantedBy = [ "sway-session.target" ];
            bindsTo = [ "sway-session.target" ];
            after = [ "sway-session.target" ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${swayRuLayout}";
              Restart = "on-failure";
              RestartSec = "2";
            };
          };
        };
      }
      (neg.mkHomeFiles {
        ".config/sway/config".text = swayConfig;
        ".config/swayfx/config".text = swayfxConfig;
        # Shared with the mango profile (files/gui/mango/); deployed here so
        # sway's `color_profile icc` can load it.
        ".config/sway/Display-P3.icc".source = config.lib.neg.path "files/gui/mango/Display-P3.icc";
      })
    ]
  );
}
