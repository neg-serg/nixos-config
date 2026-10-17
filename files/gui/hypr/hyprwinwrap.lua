-- hyprwinwrap: background-window declarations. The plugin is dlopen'd by the
-- generated hyprwinwrap-setup helper at session start and this file is pushed
-- through `hyprctl eval` right after the load — the calls cannot live in
-- hyprland.lua itself, because a plugin cannot be loaded while that file is
-- still being parsed, so hl.plugin.hyprwinwrap would be nil there.
--
-- Any window can sit behind the desktop: a video player, a browser, a shader
-- canvas. Match `class` and/or `title` exactly (not a regex — find them with
-- `hyprctl clients`); pos_*/size_* are percentages of the screen and `layer`
-- orders several background windows (higher renders on top).
--
-- Example: one full-screen background window.
--   hl.plugin.hyprwinwrap.window({
--     class = "window-bg",
--     title = "window-bg",
--     layer = 0,
--     pos_x = 0,
--     pos_y = 0,
--     size_x = 100,
--     size_y = 100,
--   })
--
-- `hl.plugin.hyprwinwrap.focus("<class-or-title>")` toggles a background
-- window forward; calling it again (or focusing anything else) sends it back.
--
-- Active declaration: the looped waterfall played by the wallpaper-video user
-- service (modules/user/session/wallpaper-video.nix). The clip is
-- ~/pic/wl/video/waterfall_loop.mp4 and the service passes the same
-- class/title/app-id.
hl.plugin.hyprwinwrap.window({
  class = "waterfall-bg",
  title = "waterfall-bg",
  layer = 0,
  pos_x = 0,
  pos_y = 0,
  size_x = 100,
  size_y = 100,
})
