-- HyprCapture settings (screenshots and screen recording).
--
-- Load-then-push, same as hyprdynamiccursors.lua: the .so is dlopen'd by the
-- generated `hyprcapture-setup` helper after hyprland.lua has been parsed, and
-- the plugin registers its config keys (plugin.hyprcapture.*) only in
-- PLUGIN_INIT — so this file is fed to `hyprctl eval` instead. Re-runnable in a
-- live session: `hyprcapture-setup`.
--
-- Only the output directories are pinned; everything else keeps upstream's
-- defaults (save + clipboard + result thumbnail on). shots/ and recordings/
-- are where the grim and screenrec flow wrote, so the pic-* helpers and the
-- existing habits keep working. Keep the values in sync with the guarded
-- re-apply in hyprland.lua.

hl.config({
  plugin = {
    hyprcapture = {
      save_dir = "$XDG_PICTURES_DIR/shots",
      record_save_dir = "$XDG_VIDEOS_DIR/recordings",
    },
  },
})
