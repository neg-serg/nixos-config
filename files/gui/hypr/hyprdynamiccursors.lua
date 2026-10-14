-- HyprDynamicCursors: stretch the cursor shape with movement (mode = "stretch").
-- Pushed with `hyprctl eval` by hyprdynamiccursors-setup right after the plugin
-- is dlopen'd — its config keys (plugin.dynamic_cursors.*) do not exist while
-- hyprland.lua is parsed, same load-then-push pattern as hyprglass.lua.

hl.config({
  plugin = {
    dynamic_cursors = {
      enabled = true,
      -- stretch: shape follows movement direction and speed
      -- (other modes: tilt, rotate, none)
      mode = "stretch",
    },
  },
})
