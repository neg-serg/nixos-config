-- HyprExpo (workspace overview) — configuration applied at session start.
--
-- Same pattern as hyprglass.lua: the plugin's own Lua namespace
-- (hl.plugin.hyprexpo.*) is not available while hyprland.lua is parsed — the
-- plugin is dlopen'd by the generated hyprexpo-setup helper AFTER the config
-- parse (modules/user/nix-maid/hyprland/main.nix), which then feeds this file
-- to `hyprctl eval`. Only the registered plugin config keys are set here; the
-- helper prepends a newline because hyprctl would read the leading "--" as a flag.
--
-- Dispatcher: hyprctl dispatch hyprexpo:expo toggle (bound to SUPER+grave in
-- hyprland.lua). The 3-finger swipe is registered as a plugin gesture with
-- direction "vertical" below, because hyprland.lua already owns the 3-finger
-- horizontal gesture (scrolling tape).
hl.config({
  plugin = {
    hyprexpo = {
      columns = 3, -- tiles per row
      rows = 0, -- follow columns (square grid)
      gaps_in = 8,
      gaps_out = 0,
      bg_col = "rgb(0d0d0d)",
      workspace_method = "center current",

      show_cursor = 1,
      cancel_key = "escape",
      keynav_enable = 1,
      number_key_mode = "workspace", -- number keys pick global workspace IDs
      skip_empty = 0, -- empty workspaces stay selectable (drag targets)
      max_workspace = 0, -- 0 = Hyprland's own workspace selector
      show_pinned_windows = 0, -- keep PiP out of the thumbnails only

      -- Frameless/zero-rounding look, matching the compositor's own style:
      -- invisible border on plain tiles, the config's navy as the highlight.
      tile_rounding = 0,
      tile_rounding_power = 2.0,
      border_width = 2,
      border_color = "rgba(00000000)",
      border_color_current = "rgba(002859cc)",
      border_color_focus = "rgba(00285981)",
      border_color_hover = "rgba(0028595f)",

      -- Follow-your-finger swipe. direction = vertical: the 3-finger
      -- horizontal swipe is already an hl.gesture() workspace bind.
      gesture_fingers = 3,
      gesture_direction = "vertical",
      gesture_distance = 200,
    },
  },
})
