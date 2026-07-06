{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  n = neg;
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.wlr-which-key # On-screen keybinding cheatsheet for Wayland
      ];
    }

    (n.mkHomeFiles {
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
          # Browsers removed (were Firefox-based, required GTK)
          - mod: SUPER
            separator: "  "
            key: x
            command: raise --match 'class:regex=^term$' --launch 'kitty --class term'
            title: Terminal
          - mod: SUPER
            separator: "  "
            key: q
            command: raise --match 'class:regex=^nwim$' --launch 'kitty --class nwim -e nvim'
            title: Neovim
          - mod: SUPER
            separator: "  "
            key: b
            command: raise --match 'class:regex=^mpv$' --launch 'pl video'
            title: Video
          - mod: SUPER
            separator: "  "
            key: g
            command: 'raise --match "class:regex=^(steam|com\\.valvesoftware\\.Steam|steam_app.*|gamescope)$" --launch steam'
            title: Steam
          - mod: SUPER
            key: o
            command: raise --match 'class:regex=^(org.pwmt.zathura)$' --launch zathura
            title: Zathura

          - mod: SUPER
            key: s
            title: Scratchpads
            children:
              - key: a
                command: hyprscratch amnezia 'amnezia-wg' special
                title: Amnezia
              - key: d
                command: hyprscratch teardown 'kitty --class teardown -e btop' special
                title: Teardown
              - key: e
                command: hyprscratch org.telegram.desktop 'Telegram' special
                title: IM
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

          - mod: SUPER
            key: p
            title: Power
            children:
              - key: l
                command: hyprlock
                title: Lock
              - key: s
                command: systemctl suspend
                title: Suspend
              - key: r
                command: systemctl reboot
                title: Reboot
              - key: S
                command: systemctl poweroff
                title: Shutdown

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

          - mod: SUPER
            key: y
            command: wl random ~/pic/wl ~/pic/black
            title: Wallpaper

          - mod: SUPER
            key: e
            title: Selectors
            children:
              - key: w
                command: hyde-selector wallpaper
                title: Wallpaper
              - key: t
                command: hyde-selector theme
                title: Theme
              - key: a
                command: hyde-selector animation
                title: Animation
              - key: e
                command: vicinae toggle
                title: Emoji
              - key: c
                command: vicinae toggle
                title: Calculator

          - mod: SUPER
            key: m
            title: Media
            children:
              - key: i
                command: pl vol mute
                title: Mute
              - key: o
                command: pl vol unmute
                title: Unmute
              - key: w
                command: 'pl cmd play-pause'
                title: Play/Pause
              - key: comma
                command: 'pl cmd previous'
                title: Previous
              - key: period
                command: 'pl cmd next'
                title: Next

          - mod: SUPER
            key: i
            title: Special
            children:
              - key: q
                command: raise --match 'class:regex=^qpwgraph$' --launch qpwgraph
                title: QPWGraph
              - key: d
                command: raise --match 'class:regex=^org\\.nicotine_plus\\.Nicotine$' --launch nicotine
                title: Nicotine+
              - key: Q
                command: raise --match 'class:regex=^Carla2$' --launch carla
                title: Carla
              - key: o
                command: raise --match 'class:regex=^(Obsidian|md\\.obsidian\\.Obsidian)$' --launch obsidian
                title: Obsidian
              - key: O
                command: raise --match 'class:regex=^(obs|com\\.obsproject\\.Studio)$' --launch obs
                title: OBS
              - key: b
                command: raise --match 'class:regex=^Bazecor$' --launch bazecor
                title: Bazecor
      '';
    })
  ];
}
