-- HyprExpo (workspace overview) — configuration applied at session start.
--
-- Same pattern as hyprglass.lua: the plugin's own Lua namespace
-- (hl.plugin.hyprexpo.*) is not available while hyprland.lua is parsed — the
-- plugin is dlopen'd by the generated hyprexpo-setup helper AFTER the config
-- parse (modules/user/nix-maid/hyprland/main.nix), which then feeds this file
-- to `hyprctl eval`. Only the registered plugin config keys are set here; the
-- helper prepends a newline because hyprctl would read the leading "--" as a flag.
--
-- Dispatcher: the `hypr-expo` helper (toggle | push | select,
-- modules/user/nix-maid/hyprland/main.nix). SUPER+grave and the workspace capsule
-- in the panel both go through it. The 3-finger swipe is registered as a plugin
-- gesture with direction "vertical" below, because hyprland.lua already owns the
-- 3-finger horizontal gesture (scrolling tape).
--
-- Mouse: the fork does not read mouse buttons on its own — it exposes a `select`
-- action that looks at the tile under the pointer, and expects a bind on the
-- mouse button (upstream README: `bind = , mouse_down, hyprexpo:expo, select`).
-- hyprland.lua binds the plain left button to it through the same helper;
-- without that bind a click inside the overview does nothing at all.



hl.config({
  plugin = {
    hyprexpo = {
      -- The grid, with workspace names on the tiles and the wallpaper behind them:
      -- the combination upstream documents for this ("For a dynamic grid with
      -- workspace labels and a wallpaper background", docs/configuration/options).
      -- dynamic_grid sizes the grid from the workspaces that exist instead of
      -- counting columns, so the layout follows the desktop rather than a fixed 3x3.
      dynamic_grid = 1,
      fill_gaps = 0,
      mru_sort = 0,
      show_workspace_names = 1,
      label_pos = "top_right",
      label_size = 48,
      wallpaper_bg = 1,

      columns = 3, -- only bounds the grid when dynamic_grid is off
      gaps_in = 5,
      gaps_out = 0,
      bg_col = "rgb(111111)",
      workspace_method = "center current",

      -- Keys the overview itself handles; the rest of its keybinds (arrows,
      -- return, escape, tile selection, the left button) live in the `hyprexpo`
      -- submap in hyprland.lua — the plugin enters it while the overview is open.
      cancel_key = "escape",
      show_cursor = 1,
      keynav_enable = 1,
      number_key_mode = "workspace", -- digits pick global workspace IDs
      keynav_wrap_h = 1,
      keynav_wrap_v = 1,
      keynav_reading_order = 0,

      -- Follow-your-finger swipe. direction = vertical: the 3-finger horizontal
      -- swipe is already an hl.gesture() workspace bind.
      gesture_fingers = 3,
      gesture_direction = "vertical",
      gesture_distance = 200,
    },
  },
})
