-- hyprglass (Apple-style liquid glass) — configuration applied at session start.
--
-- Why plain config keys and not the plugin's Lua API: `hg.config({...})`
-- (hl.plugin.hyprglass.config) aborts the compositor — SIGABRT in
-- forwardLuaConfig <- handleLuaConfig, reproduced in a nested Hyprland 0.56.2 with
-- hyprglass 0.8.1 — while setting the registered config keys goes through the
-- config manager and is stable. The plugin itself is loaded first by the generated
-- hyprglass-setup helper (modules/user/nix-maid/hyprland/main.nix), which then
-- feeds this file to `hyprctl eval`; the helper prepends a newline because hyprctl
-- would otherwise read the leading "--" comment as a flag.
hl.config({
  plugin = {
    hyprglass = {
      enabled = true,
      default_theme = "dark",
      default_preset = "default",
      manage_window_blur = true, -- glass replaces Hyprland's blur (noblur on glassed windows)
      blur_strength = 3, -- blur radius scale (value * 12 px)
      blur_iterations = 5, -- gaussian passes, capped at 5
      refraction_strength = 0.5, -- edge refraction
      chromatic_aberration = 0.3,
      fresnel_strength = 0.3,
      specular_strength = 0.1,
      glass_opacity = 0.5,
      edge_thickness = 0.05,
      lens_distortion = 0.05,
      adaptive_dim = 0.5,
      layers = {
        enabled = true,
        -- Layer surfaces (quickshell bars/panels + the notification layer)
        namespaces = "qs-panel,qs-content-left,qs-content-right,quickshell-bar-reserve,quickshell,notifications,qs-music,qs-calendar,qs-monitor,qs-weather,sideleft-weather,sysmon-popup",
        -- Above the shadow alpha, otherwise shadows trigger glass on the whole surface
        namespace_mask_thresholds = "qs-panel=0.3,qs-content-left=0.3,qs-content-right=0.3,quickshell=0.3,notifications=0.3",
      },
    },
  },
})
