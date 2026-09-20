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
      columns = 3, -- tiles per row
      rows = 0, -- follow columns (square grid)
      gaps_in = 8,
      gaps_out = 24, -- keep the grid off the screen edges, or it reads as one field
      bg_col = "rgb(0d0d0d)",
      -- Draw the wallpaper behind the tiles. Off (the plugin's default) the whole
      -- overview is the flat bg_col above, and since most of this desktop is dark
      -- windows on a dark backdrop, opening it looked like a black screen with a
      -- single thumbnail in it. With the wallpaper drawn the grid reads as the
      -- desktop itself, and the window previews sit on top of it.
      wallpaper_bg = 1,
      workspace_method = "center current",

      show_cursor = 1,
      cancel_key = "escape",
      keynav_enable = 1,
      number_key_mode = "workspace", -- number keys pick global workspace IDs
      skip_empty = 0, -- empty workspaces stay selectable (drag targets)
      max_workspace = 0, -- 0 = Hyprland's own workspace selector
      show_pinned_windows = 0, -- keep PiP out of the thumbnails only
      -- Workspace number chip per tile. Without it the tiles are unlabelled and
      -- an empty one is indistinguishable from a tile whose preview failed.
      show_workspace_numbers = 1,

      -- Frameless/zero-rounding look, matching the compositor's own style. The
      -- borders are no longer transparent: a tile edge has to be visible over the
      -- wallpaper, otherwise the previews bleed into each other.

      tile_rounding = 0,
      tile_rounding_power = 2.0,
      border_width = 2,
      border_color = "rgba(00285999)",
      border_color_current = "rgba(0074d9cc)",
      border_color_focus = "rgba(0074d999)",
      border_color_hover = "rgba(4da3ffb3)",

      -- Follow-your-finger swipe. direction = vertical: the 3-finger
      -- horizontal swipe is already an hl.gesture() workspace bind.
      gesture_fingers = 3,
      gesture_direction = "vertical",
      gesture_distance = 200,
    },
  },
})
