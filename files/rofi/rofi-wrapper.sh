#!/usr/bin/env bash
set -euo pipefail
rofi_bin="@ROFI_BIN@"
jq_bin="@JQ_BIN@"
hyprctl_bin="@HYPRCTL_BIN@"
# Fallback to PATH if not substituted by Nix
if [ "$hyprctl_bin" = "@HYPRCTL_BIN@" ] || [ -z "$hyprctl_bin" ]; then
  hyprctl_bin="${ROFI_WRAPPER_HYPRCTL:-hyprctl}"
fi
xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
xdg_conf="${XDG_CONFIG_HOME:-$HOME/.config}"
themes_dir="$xdg_data/rofi/themes"
# Default to config dir to make @import in config.rasi resolve relative files
cd_dir="$xdg_conf/rofi"
prev_is_theme=0
theme_name=""
have_cfg=0
have_kb_cancel=0
have_kb_secondary_copy=0
have_auto_select=0
have_no_auto_select=0
want_offsets=1
have_xoff=0
have_yoff=0
have_loc=0
for arg in "$@"; do
  if [ "$prev_is_theme" -eq 1 ]; then
    val="$arg"
    prev_is_theme=0
    case "$val" in
      /* | */*) : ;; # absolute or contains path component -> leave as-is
      *)
        case "$val" in *.rasi | *.rasi:*) cd_dir="$themes_dir" ;; esac
        ;;
    esac
    # remember base theme name for per-theme placement tweaks
    base=$(printf '%s' "$val" | sed -E 's#.*/##; s/\.rasi(:.*)?$//')
    [ -n "$base" ] && theme_name="$base"
  fi
  case "$arg" in
    -theme) prev_is_theme=1 ;;
    -theme=*)
      val=$(printf '%s' "$arg" | sed -e 's/^-theme=//')
      case "$val" in
        /* | */*) : ;;
        *) case "$val" in *.rasi | *.rasi:*) cd_dir="$themes_dir" ;; esac ;;
      esac
      base=$(printf '%s' "$val" | sed -E 's#.*/##; s/\.rasi(:.*)?$//')
      [ -n "$base" ] && theme_name="$base"
      ;;
    -no-config | -config | -config=*) have_cfg=1 ;;
    -xoffset | -xoffset=*) have_xoff=1 ;;
    -yoffset | -yoffset=*) have_yoff=1 ;;
    -location | -location=*) have_loc=1 ;;
    -kb-cancel | -kb-cancel=*) have_kb_cancel=1 ;;
    -kb-secondary-copy | -kb-secondary-copy=*) have_kb_secondary_copy=1 ;;
    -auto-select) have_auto_select=1 ;;
    -no-auto-select) have_no_auto_select=1 ;;
  esac
done
[ -d "$cd_dir" ] && cd "$cd_dir"

# If the caller explicitly picked the pass theme, let the theme position it
# (pass uses a top-anchored window); skip wrapper offsets in that case.
if [ "$theme_name" = "pass" ]; then
  want_offsets=0
fi

# Compute offsets from Quickshell Theme + Hyprland scale to align with panel
# Only when caller did not specify offsets explicitly
if [ "$want_offsets" -eq 1 ] && [ "$have_xoff" -eq 0 ] && [ "$have_yoff" -eq 0 ]; then
  theme_json="$xdg_conf/quickshell/Theme/.theme.json"
  # Defaults if quickshell or jq/hyprctl unavailable
  sm=18
  ay=4
  scale=1
  extra=""
  if [ -f "$theme_json" ]; then
    sm=$("$jq_bin" -r 'try .panel.sideMargin // 18' "$theme_json" 2> /dev/null || echo 18)
    ay=$("$jq_bin" -r 'try .panel.menuYOffset // 8' "$theme_json" 2> /dev/null || echo 8)
    extra=$("$jq_bin" -r 'try .panel.menuYOffsetAdjust // empty' "$theme_json" 2> /dev/null || echo "")
  fi
  if ! printf '%s' "$extra" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    # Default: subtract full menuYOffset so the menu sits flush to panel
    extra=$(awk -v a="$ay" 'BEGIN{print a}')
  fi
  # Hyprland monitor scale (focused)
  scale=$("$hyprctl_bin" -j monitors 2> /dev/null | "$jq_bin" -r 'try (.[ ] | select(.focused==true) | .scale) // 1' 2> /dev/null || echo 1)
  # reduce y-offset by adjustment (clamp >=0)
  ay=$(awk -v a="$ay" -v e="$extra" 'BEGIN{v=a-e; if(v<0)v=0; print v}')
  # Round offsets to ints
  xoff=$(printf '%.0f\n' "$(awk -v a="$sm" -v s="$scale" 'BEGIN{printf a*s}')")
  yoff=$(printf '%.0f\n' "$(awk -v a="$ay" -v s="$scale" 'BEGIN{printf -a*s}')")
  set -- "$@" -xoffset "$xoff" -yoffset "$yoff"
  # Ensure bottom-left if not specified
  if [ "$have_loc" -eq 0 ]; then
    set -- "$@" -location 7
  fi
fi

# Avoid parsing user/system config if not explicitly requested (rofi 2.0 parser is strict)
# Avoid parsing user/system config if not explicitly requested (rofi 2.0 parser is strict)
if [ "$have_cfg" -eq 0 ]; then
  set -- -no-config "$@"
fi

# Enable auto-accept by default (can be disabled with -no-auto-select)
if [ "$have_auto_select" -eq 0 ] && [ "$have_no_auto_select" -eq 0 ]; then
  set -- -auto-select "$@"
fi

# Only inject keybindings when not loading a config (avoid duplicate "already bound")
if [ "$have_cfg" -eq 0 ]; then
  # Free Control+c from default secondary-copy mapping, unless caller sets it
  if [ "$have_kb_secondary_copy" -eq 0 ]; then
    set -- -kb-secondary-copy "" "$@"
  fi
  # Ensure Ctrl+C always cancels, unless caller specified their own mapping
  if [ "$have_kb_cancel" -eq 0 ]; then
    set -- -kb-cancel "Control+c,Escape" "$@"
  fi
fi
exec "$rofi_bin" "$@"
