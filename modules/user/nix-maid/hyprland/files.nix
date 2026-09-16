{
  neg,
  config,
  ...
}:
let
  lockDir = config.lib.neg.path "files/gui/hypr/hyprlock";
  lockNames = builtins.attrNames (builtins.readDir lockDir);
in
{
  generateFileLinks =
    {
      hyprlandConfText,
      hyprlandLuaText,
    }:
    neg.mkHomeFiles (
      {
        ".config/hypr/hyprland.conf".text = hyprlandConfText;

        ".config/hypr/hyprland.lua".text = hyprlandLuaText;

        ".config/hypr/hyprlock.conf".text = config.lib.neg.readFile "files/gui/hypr/hyprlock.conf";

        ".config/hypr/hypridle.conf".text = ''
          # Hypridle — idle configuration
          # Idle locking temporarily disabled (2026-08-31): hyprlock removed.
          # No DPMS off: the monitor stays powered (avoids the DPMS wake-up bug).
          # Restore the auto-lock by re-adding the lock_cmd + 120 s listener from
          # git history together with the hyprlock package.
        '';

        # Hyprscratch config: Telegram scratchpad (name without dots — togglespecialworkspace breaks on '.')
        ".config/hypr/hyprscratch.conf".text = ''
          telegram {
              class = org.telegram.desktop
              command = Telegram
              options = special
              # Fresh spawns land right-aligned; user geometry (saved by
              # scratchpad-geometry.service) wins once the window is moved.
              rules = size monitor_w*0.3 monitor_h-60; move monitor_w*0.7-8 8
          }
          music {
              class = music
              offset = 0 30%
          }
        '';

        # Ensure local.d directory exists with at least one .lua file so the glob never fails
        ".config/hypr/local.d/00-override.lua".text =
          "-- Local Hyprland overrides (Lua API)
-- Use hl.env(), hl.config(), hl.bind(), hl.window_rule() etc.
-- See ~/.config/hypr/hyprland.lua for reference
";
      }
      // (neg.mkDirLinks ".config/hypr/hyprlock" lockDir lockNames)
    );
}
