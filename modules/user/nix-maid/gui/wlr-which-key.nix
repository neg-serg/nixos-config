{
  pkgs,
  lib,
  neg,
  ...
}:

{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.wlr-which-key # On-screen keybinding cheatsheet for Wayland
      ];
    }

    (neg.mkHomeFiles {
      ".config/wlr-which-key/config.yaml".text = ''
        font: Iosevka
        font_size: 12
        border: #7aa2f7
        background: #1a1b26e6
        foreground: #c0caf5
        separator: "  "
        rows_per_column: 8
        anchor: center
        margin_left: 0
        margin_right: 30
        margin_top: 160

        keys:
          # ── Launchers (SUPER) ─────────────────────────────────────
          - mod: SUPER
            key: Return
            command: kitty
            title: Terminal
          - mod: SUPER
            key: q
            command: raise --match 'class:regex=^nwim$' --launch 'kitty --class nwim -e nvim'
            title: Neovim
          - mod: SUPER
            key: w
            command: raise --match 'class:regex=^vivaldi$' --launch vivaldi
            title: Browser
          - mod: SUPER
            key: x
            command: raise --match 'class:regex=^term$' --launch 'kitty --class term'
            title: Terminal (raise)
          - mod: SUPER
            key: b
            command: raise --match 'class:regex=^mpv$' --launch 'pl video'
            title: Video
          - mod: SUPER
            key: g
            command: 'raise --match "class:regex=^(steam|com\\.valvesoftware\\.Steam|steam_app.*|gamescope)$" --launch steam'
            title: Steam

          # ── Navigation (SUPER) ────────────────────────────────────
          - mod: SUPER
            key: h
            command: hyprctl dispatch movefocus l
            title: Focus left
          - mod: SUPER
            key: j
            command: hyprctl dispatch movefocus d
            title: Focus down
          - mod: SUPER
            key: k
            command: hyprctl dispatch movefocus u
            title: Focus up
          - mod: SUPER
            key: l
            command: hyprctl dispatch movefocus r
            title: Focus right
          - mod: SUPER
            key: Tab
            command: hyprctl dispatch cyclenext
            title: Cycle windows
          - mod: ALT
            key: Tab
            command: hyprctl dispatch workspace previous
            title: Prev workspace

          # ── Scratchpads (SUPER) ───────────────────────────────────
          - mod: SUPER
            key: d
            title: Scratchpads
            children:
              - key: d
                command: hyprscratch teardown 'kitty --class teardown -e btop' special
                title: Btop
              - key: e
                command: hyprscratch toggle telegram
                title: IM (Telegram)
              - key: f
                command: hyprscratch music 'kitty --class music -e rmpc' special
                title: Music
              - key: t
                command: hyprscratch torrment 'kitty --class torrment -e rustmission' special
                title: Torrents
              - key: u
                command: hyprscratch vpn 'kitty --class vpn -e sing-box tun' special
                title: VPN
              - key: p
                command: 'hyprscratch mixer "kitty --class mixer -e ncpamixer" special'
                title: Mixer
              - key: H
                command: hyprscratch hide-all
                title: Hide all

          # ── Screenshots (SUPER+SHIFT) ────────────────────────────
          - mod: SUPER
            key: r
            title: Screenshots
            children:
              - key: r
                command: 'shot="$HOME/pic/shots/satty-$(date +%Y%m%d-%H.%M.%S).png"; grimblast save screen "$shot" && pic-info "$shot"'
                title: Screen
              - key: R
                command: 'shot="$HOME/pic/shots/satty-$(date +%Y%m%d-%H.%M.%S).png"; grimblast save area "$shot" && pic-info "$shot"'
                title: Area
              - key: v
                command: screenrec screen
                title: Record Screen
              - key: V
                command: screenrec area
                title: Record Area

          # ── Power (SUPER) ────────────────────────────────────────
          - mod: SUPER
            key: Escape
            title: Window
            children:
              - key: Escape
                command: hyprctl dispatch killactive
                title: Close window
              - key: r
                command: hyprctl dispatch fullscreen
                title: Fullscreen
              - key: p
                command: pass-2col
                title: Password

          # ── Media (SUPER+SHIFT) ──────────────────────────────────
          - mod: SUPER
            key: period
            title: Media
            children:
              - key: w
                command: 'pl cmd play-pause'
                title: Play/Pause
              - key: comma
                command: 'pl cmd previous'
                title: Previous
              - key: period
                command: 'pl cmd next'
                title: Next
              - key: i
                command: pl vol mute
                title: Mute
              - key: o
                command: pl vol unmute
                title: Unmute

          # ── Misc (SUPER+CTRL) ────────────────────────────────────
          - mod: SUPER
            key: o
            title: Apps (CTRL)
            children:
              - key: o
                command: raise --match 'class:regex=^(obs|com\\.obsproject\\.Studio)$' --launch obs
                title: OBS
              - key: n
                command: raise --match 'class:regex=^(Obsidian|md\\.obsidian\\.Obsidian)$' --launch 'flatpak run md.obsidian.Obsidian'
                title: Obsidian
              - key: c
                command: raise --match 'class:regex=^swayimg$' --launch 'swayimg ~/dw'
                title: Swayimg
              - key: v
                command: raise --match 'class:regex=^Bazecor$' --launch bazecor
                title: Bazecor
              - key: d
                command: hyprctl dispatch splitratio -0.1
                title: Split -
              - key: f
                command: hyprctl dispatch splitratio +0.1
                title: Split +
              - key: p
                command: 'raise --match "class:regex=^Carla2$" --launch carla'
                title: Patchbay

          # ── Wallpaper ────────────────────────────────────────────
          - mod: SUPER
            modifier: SHIFT
            key: c
            command: wl random ~/pic/wl
            title: Wallpaper random

          # ── Notifications ────────────────────────────────────────
          - mod: SUPER
            key: n
            command: dunstctl history-pop
            title: Notifications
          - mod: SUPER
            key: space
            command: dunstctl close-all
            title: Close all
      '';
    })
  ];
}
