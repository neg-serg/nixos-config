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
      -- Packaged option (modules/user/nix-maid/hyprland/hyprexpo-grid-overview.patch):
      -- 1 = draw the grid even for workspaces with the native scrolling layout,
      -- which upstream would open as its scrolling overview (a strip of columns).
      -- On: with the config read fixed (see the patch header) the grid opens on a
      -- scrolling workspace — verified in the live session (submap default ->
      -- hyprexpo, 69% of the frame redrawn, no crash), and the nested run that
      -- suggested otherwise had too few workspaces for a grid to have any tiles.
      grid_overview = 1,

      dynamic_grid = 1,
      -- Empty workspaces are drawn as tiles and can be selected like any other
      -- (upstream skips them): that is what makes the grid a place to *put* windows
      -- rather than just a picture of the ones that exist.
      skip_empty = 0,
      -- Token labels on the tiles — the a s d f g / q w e r t / z x c v b keys in
      -- the submap jump straight to a tile by its label.
      selection_label_enable = 1,
      fill_gaps = 0,
      mru_sort = 0,
      show_workspace_names = 1,
      label_pos = "top_right",
      label_size = 48,
      wallpaper_bg = 1,

      columns = 3, -- only bounds the grid when dynamic_grid is off
      gaps_in = 5,
      -- Outer inset: the grid floats a little away from the screen edges instead of
      -- touching them (0 = edge to edge). Logical pixels — 16 reads as a calm margin
      -- on the 4K panel at scale 2.
      gaps_out = 16,
      -- Backdrop behind the tiles when there is no wallpaper to show (wallpaper_bg = 1
      -- paints the wallpaper itself): the neg canvas, not a flat grey.
      bg_col = "rgb(000000)",

      -- Frames. This fork only frames the tiles that carry state — the workspace you
      -- came from, the keyboard-focused one and the hovered one; idle tiles stay bare
      -- (border_color is unused by the renderer, kept only as documentation). Colours
      -- are the neg roles, and the two loud states get a 45° two-stop gradient the
      -- plugin accepts as "rgba(...) rgba(...) <deg>" (parseGradientSpec). Corners
      -- stay square because the desktop itself runs border_size = 0, rounding = 0
      -- (hyprland.lua); tile_rounding = 8 would make rounded cards instead.
      -- 2px is 4 physical pixels at scale 2 — the same thin weight as the rest of the
      -- desktop's hairlines.
      border_width = 2,
      border_color = "rgba(1c334eff)",     -- unused for idle tiles (see above)
      border_color_hover = "rgba(367cb0ff)", -- ops1: quiet, the pointer is enough
      border_color_current = "rgba(005fafff) rgba(367cb0ff) 45deg", -- ops3 -> ops1
      border_color_focus = "rgba(d1e5ffff) rgba(a5c1e6ff) 45deg",   -- whit -> high
      tile_rounding = 0,
      tile_rounding_power = 2.0,

      -- Drag/drop preview: upstream paints it flat green, which is the only green in
      -- the whole rice. ops3 at 14% alpha, the active target a touch stronger, and the
      -- dragged tile keeps the focus frame (drag_drop_source_border_color empty falls
      -- back to border_color_focus).
      drag_drop_proxy_color = "rgba(005faf24)",
      drag_drop_proxy_active_color = "rgba(367cb03d)",
      drag_drop_proxy_border_color = "rgba(005fafff)",
      drag_drop_proxy_border_width = 2,
      drag_drop_proxy_rounding = 0,

      -- Labels: the terminal font, text in the palette's whites, selection tokens in
      -- the accent colour instead of the upstream orange (they are the same tokens the
      -- hyprexpo submap jumps by).
      label_font_family = "Iosevka",
      label_color = "rgba(d1e5ffff)", -- whit: the palette's light text
      -- The per-state label colours default to upstream cyan/orange, which is the one
      -- thing that visibly fights the palette; keep them inside it.
      label_color_hover = "rgba(a5c1e6ff)",
      label_color_focus = "rgba(d1e5ffff)",
      label_color_current = "rgba(a5c1e6ff)",
      workspace_number_color = "rgba(7387a1ff)", -- darkhigh: muted numbers
      label_bg_color = "rgba(15181f88)", -- translucent dnorm, not pure black
      selection_label_color = "rgba(a5c1e6ff)", -- tokens in the accent, not orange
      workspace_method = "center current",

      -- Keys the overview itself handles; the rest of its keybinds (arrows,
      -- return, escape, tile selection, the left button) live in the `hyprexpo`
      -- submap in hyprland.lua — the plugin enters it while the overview is open.
      -- The fork handles the mouse itself: a press picks the tile under the cursor,
      -- and that same press is what drags a window from one workspace tile to
      -- another. On, by choice — the price is that a click on the panel capsule can
      -- also pick the tile sitting under the bar and move you there, so the tilde
      -- (SUPER+grave) stays the clean way into the overview. 0 = keyboard-only.
      drag_drop_enable = 1,
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
