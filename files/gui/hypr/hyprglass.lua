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
      -- 6 (72 px): 3 left the frost barely readable behind the surfaces and 4 was
      -- still short of what reads as frosted glass, which is what "the special
      -- glass blur is missing" turned out to mean.
      blur_strength = 6, -- blur radius scale (value * 12 px)
      -- Frosted tint. Off by default (-1) in the plugin, which is why the glass
      -- read as plain transparency with a blur. Density comes from here and from
      -- glass_opacity below, not from a wider radius: 0.5 with 0.65 opacity is
      -- what makes it read as frosted rather than merely blurred.
      vibrancy = 0.5,
      -- ...but only against the dark theme: the same tint washes the light one
      -- out, so there it stays off.
      light = { vibrancy = -1 },
      blur_iterations = 5, -- gaussian passes, capped at 5
      refraction_strength = 0.5, -- edge refraction
      chromatic_aberration = 0.3,
      fresnel_strength = 0.3,
      specular_strength = 0.1,
      -- Overall amount of glass on a surface (0.5 was the plugin default).
      glass_opacity = 0.65,
      edge_thickness = 0.05,
      lens_distortion = 0.05,
      adaptive_dim = 0.5,
      layers = {
        enabled = true,
        -- Layer surfaces: popups/notifications only. The always-on bar surfaces
        -- (qs-panel, quickshell-bar-reserve, qs-content-left/right) are deliberately
        -- excluded: hyprglass's layer pass re-samples the background between frames,
        -- so the glass there flickered between none / normal / double strength (0.56.2
        -- + hyprglass 0.8.1, measured 2026-09-17). Those surfaces keep Hyprland's
        -- own layer blur (layerrule blur-qs-.* , ignore_alpha 0.6) instead.
        namespaces = "quickshell,notifications,qs-music,qs-calendar,qs-monitor,qs-weather,sideleft-weather,sysmon-popup",
        -- Above the shadow alpha, otherwise shadows trigger glass on the whole surface
        namespace_mask_thresholds = "quickshell=0.3,notifications=0.3,qs-music=0.3",
        -- The layer pass re-samples the backdrop between frames and the result
        -- reads as a ghost of whatever is behind the surface (the bar was taken
        -- out of this pass for the same reason). Off: the glass still blurs and
        -- refracts, it just stops chasing every frame.
        live_resample = false,
      },
    },
  },
})
