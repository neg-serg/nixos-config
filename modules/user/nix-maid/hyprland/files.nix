{
  neg,
  ...
}:
let
  animDir = ../../../../files/gui/hypr/animations;
  lockDir = ../../../../files/gui/hypr/hyprlock;

  mkFiles =
    destDir: sourceDir: files:
    files
    |> map (f: {
      name = "${destDir}/${f}";
      value = {
        source = sourceDir + "/${f}";
      };
    })
    |> builtins.listToAttrs;
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

        ".config/hypr/hyprlock.conf".text = ''
          # Hyprlock Configuration
          # All config is inlined — source/glob directives don't work
          # reliably with Nix-store symlinks and/or hyprlock v0.9.5
          # tilde expansion, so we keep everything in one file.

          $fontFamily = Iosevka

          # Colors from quickshell theme
          $textPrimary = rgba(203, 214, 229, 1.0)
          $textSecondary = rgba(174, 185, 200, 0.8)
          $textDim = rgba(174, 185, 200, 0.6)
          $surface = rgba(24, 28, 37, 0.95)
          $accent = rgba(0, 111, 204, 1.0)
          $accentDim = rgba(0, 111, 204, 0.8)
          $outline = rgba(59, 76, 92, 0.8)
          $success = rgba(14, 107, 77, 0.8)
          $error = rgba(255, 107, 129, 0.8)
          $warning = rgba(255, 200, 100, 0.8)

          general {
              hide_cursor = true
              ignore_empty_input = true
              immediate_render = true
          }

          # Custom animations
          animations {
              enabled = true
              bezier = smoothDots, 0.4, 0.0, 0.2, 1.0
              bezier = smoothFade, 0.25, 0.1, 0.25, 1.0
              animation = inputFieldDots, 1, 3, smoothDots
              animation = fadeIn, 1, 4, smoothFade
              animation = fadeOut, 1, 3, smoothFade
          }

          # Background - screenshot blur (no external wallpaper needed)
          background {
              monitor =
              path = screenshot
              blur_passes = 3
              blur_size = 8
              brightness = 0.7
              noise = 0.02
          }

          # Time
          label {
              monitor =
              text = $TIME
              color = $textPrimary
              font_size = 96
              font_family = $fontFamily
              position = 0, 150
              halign = center
              valign = center
          }

          # Date
          label {
              monitor =
              text = cmd[update:43200000] date +"%A, %d %B %Y"
              color = $textSecondary
              font_size = 24
              font_family = $fontFamily
              position = 0, 50
              halign = center
              valign = center
          }

          # Greeting
          label {
              monitor =
              text = cmd[update:60000] echo "Good $(date +%H | awk '{if ($1 < 12) print "Morning"; else if ($1 < 18) print "Afternoon"; else print "Evening"}'), $USER"
              color = $textSecondary
              font_size = 20
              font_family = $fontFamily
              position = 0, -50
              halign = center
              valign = center
          }

          # Input field
          input-field {
              monitor =
              size = 300, 50
              outline_thickness = 3
              dots_size = 0.33
              dots_spacing = 0.15
              dots_center = true
              dots_rounding = -1
              outer_color = $accentDim
              inner_color = $surface
              font_color = $textPrimary
              fade_on_empty = true
              fade_timeout = 1000
              placeholder_text = <i>Password...</i>
              hide_input = false
              rounding = 15
              check_color = $success
              fail_color = $error
              fail_text = <i>$FAIL <b>($ATTEMPTS)</b></i>
              fail_timeout = 3000
              capslock_color = $warning
              position = 0, -150
              halign = center
              valign = center
          }

          # Keyboard layout indicator
          label {
              monitor =
              text = $LAYOUT
              color = $textDim
              font_size = 14
              font_family = $fontFamily
              position = 30, 30
              halign = left
              valign = bottom
          }
        '';

        ".config/hypr/hypridle.conf".text = ''
          # Hypridle — OLED-friendly idle configuration
          # 2 min idle → auto-lock
          # 3 min idle → DPMS off (OLED pixels fully off)
          # Any input wakes the display back to the lock screen

          general {
              lock_cmd = pidof hyprlock || hyprlock
          }

          listener {
              timeout = 120
              on-timeout = pidof hyprlock || hyprlock
          }

          listener {
              timeout = 180
              on-timeout = hyprctl dispatch dpms off
              on-resume = hyprctl dispatch dpms on
          }
        '';

        # Hyprscratch config: Telegram scratchpad (name without dots — togglespecialworkspace ломается на '.')
        ".config/hypr/hyprscratch.conf".text = ''
          telegram {
              class = org.telegram.desktop
              command = Telegram
              options = special
          }
        '';

        # Ensure local.d directory exists with at least one .conf file so the glob never fails
        ".config/hypr/local.d/00-override.conf".text =
          "# Local Hyprland overrides (Lua API)\n# Use hl.env(), hl.config(), hl.bind(), hl.window_rule() etc.\n# See ~/.config/hypr/hyprland.lua for reference\n";
      }
      // (mkFiles ".config/hypr/animations" animDir (builtins.attrNames (builtins.readDir animDir)))
      // (mkFiles ".config/hypr/hyprlock" lockDir (builtins.attrNames (builtins.readDir lockDir)))
    );
}
