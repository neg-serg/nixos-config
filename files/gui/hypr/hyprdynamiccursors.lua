-- HyprDynamicCursors: stretch the cursor shape with movement (mode = "stretch").
-- Pushed with `hyprctl eval` by hyprdynamiccursors-setup right after the plugin
-- is dlopen'd — its config keys (plugin.dynamic_cursors.*) do not exist while
-- hyprland.lua is parsed, same load-then-push pattern as hyprglass.lua.
-- Keep these values in sync with the guarded re-apply in hyprland.lua, which
-- restores them after a config reload drops the runtime push.
--
-- enabled = false on purpose: the stretch is a desktop effect that reads as
-- noise while gaming (fast mouse movement visibly deforms the pointer) and the
-- plugin has no per-window switch, so a game cannot opt out while the desktop
-- keeps it. Opt in for the session with `cursor-stretch on` (no hotkey on
-- purpose); that flips the live plugin config only, so a reload lands back here,
-- on off.

hl.config({
  plugin = {
    dynamic_cursors = {
      enabled = false,
      -- stretch: shape follows movement direction and speed
      -- (other modes: tilt, rotate, none)
      mode = "stretch",
      -- Shake to find magnifies the cursor (shake.base = 4x and growing) and
      -- its KDE-style detector (src/other/Shake.cpp) fires on fast circling:
      -- trail/diagonal > shake.threshold within a second. That read as "the
      -- cursor gets bigger when I spin it", so magnification is off; the
      -- stretch mode itself stays.
      shake = { enabled = false },
    },
  },
})
