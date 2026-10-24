-- hyprliquid — Liquid Glass / Acrylic / Mica / Aero materials, for windows and
-- layer surfaces.
--
-- Why this plugin and not hyprglass: hyprglass glasses only windows and popups
-- now (`manage_window_blur`), so the bar — a layer surface — had no compositor
-- glass at all and leaned on Hyprland's plain blur. hyprliquid matches layer
-- namespaces, which is the only handle a layer surface gives.
--
-- Loaded and applied by the generated `hyprliquid-setup` helper from the
-- session-start hook, like every other plugin here: a plugin cannot be dlopen'd
-- while hyprland.lua is still being parsed, and this file is pushed afterwards
-- through `hyprctl eval`.
--
-- Namespace: every pleamar surface is `pleamar` — the bar, the drawers, the
-- launcher, the lock. The rule reaches all of them; the bar is the one it was
-- written for. Narrowing it needs the scene to name its surfaces apart, which the
-- port does not do yet.
hl.config({
  plugin = {
    hyprliquid = {
      enabled = true,
    },
  },
})

if hl.plugin.hyprliquid then
  hl.layer_rule({
    name = "pleamar-liquid",
    match = { namespace = "pleamar" },
    ["hyprliquid:effect"] = "liquid_glass",
    ["hyprliquid:corner_radius"] = 12,
    ["hyprliquid:highlight_style"] = 4,
  })
end
