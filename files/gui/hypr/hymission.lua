-- hymission: overview settings and trackpad gestures. The plugin is dlopen'd by
-- the generated hymission-setup helper at session start and this file is pushed
-- through `hyprctl eval` right after the load — the calls cannot live in
-- hyprland.lua itself, because PLUGIN_INIT registers plugin.hymission.* (and
-- asks for a config reload) only once the .so is loaded.
--
-- A compositor reload keeps the plugin loaded but resets its config to the
-- defaults, so re-run `hymission-setup` to apply this file again. An unknown key
-- aborts the eval, so add new ones from the plugin's README ("Configuration")
-- deliberately.
--
-- The whole upstream key set with its defaults (geometry, layout engines,
-- appearance, colours, Stage strip, debug flags) is documented there; only the
-- keys this setup overrides are listed below, uncomment to use:
--
--   hl.config({
--     plugin = {
--       hymission = {
--         outer_padding_top = 32,          -- gap below the reserved search header
--         workspace_strip_anchor = "left",
--         workspace_strip_thickness = 160,
--         selected_expand_scale = 1.18,
--         backdrop_blur = 0,
--         backdrop_color = "rgba(00000026)",
--       },
--     },
--   })
--
-- Gestures: three-finger vertical opens/closes the overview on the current
-- workspace scope. Three-finger horizontal stays with Hyprland (the native
-- workspace swipe in hyprland.lua) and ALT+three-finger-down stays with close.
hl.plugin.hymission.gesture({
  fingers = 3,
  direction = "vertical",
  action = "toggle",
})
