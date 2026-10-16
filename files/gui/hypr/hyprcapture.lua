-- HyprCapture settings (screenshots and screen recording).
--
-- Load-then-push, same as hyprdynamiccursors.lua: the .so is dlopen'd by the
-- generated `hyprcapture-setup` helper after hyprland.lua has been parsed, and
-- the plugin registers its config keys (plugin.hyprcapture.*) only in
-- PLUGIN_INIT — so this file is fed to `hyprctl eval` instead. Re-runnable in a
-- live session: `hyprcapture-setup`.
--
-- The output directories are pinned; save and clipboard keep upstream's
-- defaults. shots/ and recordings/ are where the grim and screenrec flow wrote,
-- so the pic-* helpers and the existing habits keep working. Keep the values in
-- sync with the guarded re-apply in hyprland.lua.
--
-- The plugin's own feedback is off: screenshots get the fast quickshell
-- ScreenshotToast instead (pic-info, fired by the screenshot-toast.path unit in
-- main.nix) — the plugin notification and the result thumbnail would only
-- double the feedback the grim flow used to give instantly. Recordings keep
-- their status notifications; the thumbnail goes away for them too (the record
-- binds use screenrec, not HyprCapture).

hl.config({
  plugin = {
    hyprcapture = {
      save_dir = "$XDG_PICTURES_DIR/shots",
      record_save_dir = "$XDG_VIDEOS_DIR/recordings",
      screenshot_notification = false,
      show_thumbnail = false,
    },
  },
})
