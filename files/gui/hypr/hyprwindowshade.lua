-- HyprWindowShade — per-window, per-layer and per-class fragment shaders.
--
-- Load-then-push, same as hyprglass and hyprexpo: the .so is dlopen'd by the
-- generated `hyprwindowshade-setup` helper *after* hyprland.lua has been parsed,
-- so hl.plugin.HyprWindowShade.* is nil while the config is read — this file is
-- fed to `hyprctl eval` instead. Re-runnable in a live session:
-- `hyprwindowshade-setup`.
--
-- Shader paths have to be absolute; SHADERS points at the directory nix-maid
-- links from files/gui/hypr/shaders.
-- Tags used below: `+shader:` applies always, `+shader_inactive:` only while the
-- window is unfocused. `hl.window_rule` is Hyprland's own rule table (0.56 Lua
-- config), the plugin only adds the tag vocabulary.

local SHADERS = (os.getenv("HOME") or "") .. "/.config/hypr/shaders/"

-- Terminals (kitty --class term / nwim) recede while they are not focused. The
-- shader stays attached and blends on is_active, so focusing one is a smooth
-- ramp rather than a cut.
hl.window_rule({
  name = "shade-dim-terminals",
  match = { class = "^(term|nwim)$" },
  tag = "+shader:" .. SHADERS .. "dim_unfocused.glsl",
})

-- Telegram pixelates while unfocused: whatever is on screen stops being
-- readable the moment you look elsewhere. Remove the rule to disable it.
hl.window_rule({
  name = "shade-pixelate-telegram",
  match = { class = "^(org.telegram.desktop)$" },
  tag = "+shader_inactive:" .. SHADERS .. "pixelate.glsl",
})
