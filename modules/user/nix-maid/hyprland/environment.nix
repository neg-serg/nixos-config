{ ... }: {
  hyprlandConf = ''
    # Hyprland 0.55+ auto-detects ~/.config/hypr/hyprland.lua and uses it as
    # the config, IGNORING this legacy hyprlang .conf (the running log shows
    # "Using lua config found at .../hyprland.lua"). Consequently the old
    # `plugin = ...` and `source = ...` lines below had no effect and plugins
    # were never loaded — that is why hl.plugin.hyprspace was nil.
    #
    # Plugins are now loaded from the Lua config via hl.plugin.load(...)
    # (see hyprland.lua). This file is kept as an empty placeholder in case
    # the Lua config is ever removed.
  '';
}
