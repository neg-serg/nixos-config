{
  neg,
  config,
  ...
}:
let
  animDir = config.lib.neg.path "files/gui/hypr/animations";
  lockDir = config.lib.neg.path "files/gui/hypr/hyprlock";

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
          $surface = rgba(24, 28, 37, 0.95)
          $accentDim = rgba(0, 111, 204, 0.8)
          $success = rgba(14, 107, 77, 0.8)
          $error = rgba(255, 107, 129, 0.8)
          $warning = rgba(255, 200, 100, 0.8)

          general {
              hide_cursor = true
              ignore_empty_input = true
              # No immediate_render: the desktop screenshot is gathered before the
              # session locks, so the blackout fade starts from the live desktop
              # (no black flash while the screenshot loads).
          }

          # Custom animations
          # Fade duration = 100 ms × speed → fadeIn 30 ≈ 3 s gradual blackout,
          # fadeOut 3 ≈ 300 ms snappy wake-up.
          animations {
              enabled = true
              bezier = smoothDots, 0.4, 0.0, 0.2, 1.0
              bezier = smoothFade, 0.25, 0.1, 0.25, 1.0
              animation = inputFieldDots, 1, 3, smoothDots
              animation = fadeIn, 1, 30, smoothFade
              animation = fadeOut, 1, 3, smoothFade
          }

          # Background — solid black. The lock screen *is* the blackout: while the
          # fadeIn animation runs, the frozen desktop screenshot is drawn under a
          # black overlay whose alpha follows the fade progress, so the whole
          # display gradually darkens to black and then stays pure black. The
          # monitor itself is never powered off (no DPMS — avoids the DPMS
          # wake-up bug). The fade animations keep screencopy enabled, which is
          # what makes this transition possible.
          background {
              monitor =
              color = rgb(0, 0, 0)
          }

          # No clock/date/greeting widgets — the lock screen is deliberately a
          # plain black screen; the password field below fades in on input.

          # Input field — the only widget on the lock screen. fade_on_empty makes
          # it invisible on the black screen; typing fades it back in.
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
              # fail_timeout is not an input-field option in hyprlock 0.9.5
              # (general:fail_timeout = 2000 ms applies instead)
              capslock_color = $warning
              position = 0, 0
              halign = center
              valign = center
          }
        '';

        ".config/hypr/hypridle.conf".text = ''
          # Hypridle — idle configuration
          # 2 min idle → auto-lock with the black fade-out lock screen
          # (see hyprlock.conf). No DPMS off: the monitor stays powered and
          # the lock screen itself is the blackout — avoids the DPMS
          # wake-up bug. Wake: press any key (password field fades in)
          # and type the password.

          general {
              lock_cmd = pidof hyprlock || hyprlock
          }

          listener {
              timeout = 120
              on-timeout = pidof hyprlock || hyprlock
          }
        '';

        # Hyprscratch config: Telegram scratchpad (name without dots — togglespecialworkspace ломается на '.')
        ".config/hypr/hyprscratch.conf".text = ''
          telegram {
              class = org.telegram.desktop
              command = Telegram
              options = special
          }
          music {
              class = music
              offset = 0 30%
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
