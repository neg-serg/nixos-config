{
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features;
  filesRoot = ../../../../files;
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.games.dosemu.enable or false) (
      n.mkHomeFiles {
        ".dosemu/disclaimer".source = "${filesRoot}/dosemu/disclaimer";
        ".dosemu/boot.log".source = "${filesRoot}/dosemu/boot.log";
        ".dosemu/drive_c/autoexec.bat".source = "${filesRoot}/dosemu/drive_c/autoexec.bat";
        ".dosemu/drive_c/config.sys".source = "${filesRoot}/dosemu/drive_c/config.sys";
      }
    ))

    (n.mkHomeFiles {
      # Dosbox Config
      ".config/dosbox".source = ../../../../files/config/dosbox;

      # WezTerm Config (Synced with Kitty)
      ".config/wezterm/wezterm.lua".text = ''
        local wezterm = require 'wezterm'
        return {
          font = wezterm.font 'Iosevka Medium',
          font_size = 13.0,
          enable_tab_bar = false,
          window_decorations = "RESIZE",
          window_padding = { left = 0, right = 0, top = 0, bottom = 0 },
          colors = {
            foreground = '#6C7E96',
            background = '#000000',
            cursor_bg = '#4842ff',
            cursor_fg = '#000000',
            selection_fg = '#367bbf',
            selection_bg = '#0d1824',
            ansi = { '#020202', '#8A2F58', '#287373', '#914E89', '#395573', '#5E468C', '#31658C', '#899CA1' },
            brights = { '#3D3D3D', '#CF4F88', '#53A6A6', '#BF85CC', '#477AB3', '#7E62B3', '#6096BF', '#617287' },
          },
        }
      '';


    })
  ];
}
