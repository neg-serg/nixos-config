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

-- No class gets a shader by default any more. The terminals used to carry
-- `+shader:dim_unfocused.glsl`, which dimmed and desaturated them whenever they
-- lost focus — including every time a scratchpad (telegram/music/…) was pulled
-- up, which reads as the whole desk going dark. The shader itself is still in
-- ~/.config/hypr/shaders, so `shade on dim_unfocused` brings it back for the
-- focused window on demand.
-- Telegram pixelates while unfocused: whatever is on screen stops being
-- readable the moment you look elsewhere. Remove the rule to disable it.
hl.window_rule({
  name = "shade-pixelate-telegram",
  match = { class = "^(org.telegram.desktop)$" },
  tag = "+shader_inactive:" .. SHADERS .. "pixelate.glsl",
})

-- Scratchpad windows: an ultraviolet shadow from inside the frame. The
-- compositor draws no shadow here (decoration.shadow is off by design, see
-- hyprland.lua) and a shader cannot paint outside the window box, so the depth
-- is a violet rim lit from the top edge plus a contact shade along the edges.
-- Classes mirror the scratchpad patterns in hyprland.lua's `m` table; the list
-- is duplicated on purpose because this file is pushed standalone by
-- hyprwindowshade-setup.
local SCRATCHPAD_CLASSES = {
  "org\\.telegram\\.desktop", "TelegramDesktop", "KotatogramDesktop", "Skype", "Slack", "zoom",
  "music", "rmpc", "ncmpcpp", "mutterfox", "neomutt", "ncpamixer", "com\\.saivert\\.pwvucontrol",
  "torrment", "rebuild", "teardown", "vpn",
}
hl.window_rule({
  name = "shade-uv-shadow-scratchpads",
  match = { class = "^(" .. table.concat(SCRATCHPAD_CLASSES, "|") .. ")$" },
  tag = "+shader:" .. SHADERS .. "uv_shadow.glsl",
})
