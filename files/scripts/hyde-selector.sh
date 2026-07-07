#!/usr/bin/env bash

# HyDE-style Selector Script for NixOS
# Mimics the visual behavior of HyDE's selectors

# Rofi migration: using vicinae dmenu instead

usage() {
  echo "Usage: $0 [wallpaper|theme|animation]"
  exit 1
}

case "$1" in
  wallpaper)
    # Assuming wallpapers are in ~/pic/wallpapers or similar
    # For NixOS, we might need to find where the user keeps them
    WP_DIR="$HOME/pic/wallpapers"
    if [ ! -d "$WP_DIR" ]; then
      WP_DIR="$HOME/Pictures/Wallpapers"
    fi

    selected=$(find "$WP_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \) -printf '%f\n' | sort \
      | vicinae dmenu -p "Wallpaper")

    if [ -n "$selected" ]; then
      # Assuming swww is used
      if command -v swww > /dev/null; then
        swww img "$WP_DIR/$selected" --transition-type grow --transition-pos "$(hyprctl cursorpos | sed 's/,//g')"
        # Save wallpaper for hyprlock
        mkdir -p "$HOME/.cache/hyde"
        ln -sf "$WP_DIR/$selected" "$HOME/.cache/hyde/wall.set.png"

        # Trigger Wallbash
        if command -v wallust > /dev/null; then
          wallust run "$WP_DIR/$selected" > /dev/null 2>&1 &
          notify-send "Wallbash" "Applying colors from $selected..."

          # Wait a bit for wallust to finish (could be improved)
          sleep 1

          # Reload Kitty
          pkill -USR1 kitty || true

          # Reload Dunst
          # killall dunst; notify-send "Dunst reloaded" # Restarting might be abrupt
          # Dunst hot reloads config changes if running? No, usually needs restart.
          systemctl --user restart dunst || true
        fi
      elif command -v hyprpaper > /dev/null; then
        # This requires hyprctl hyprpaper commands
        true
      fi
    fi
    ;;

  animation)
    ANIM_DIR="$HOME/.config/hypr/animations"
    if [ -d "$ANIM_DIR" ]; then
      selected=$(find "$ANIM_DIR" -maxdepth 1 -name "*.conf" ! -name "selected.conf" -printf '%f\n' | sed 's/\.conf$//' | sort \
        | vicinae dmenu -p "Animation")

      if [ -n "$selected" ]; then
        target="$ANIM_DIR/${selected}.conf"
        if [ -f "$target" ]; then
          ln -sf "$target" "$ANIM_DIR/selected.conf"
          notify-send "Animation set to $selected"
        fi
      fi
    else
      notify-send "Animation directory not found"
    fi
    ;;

  theme)
    # This is harder on NixOS without full HyDE machinery
    # We can list available themes in ~/.config/hyde/themes or similar if they exist
    THEME_DIR="$HOME/.config/hyde/themes"
    if [ -d "$THEME_DIR" ]; then
      selected=$(find "$THEME_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort \
        | vicinae dmenu -p "Theme")

      if [ -n "$selected" ]; then
        # Handle theme switch
        notify-send "Theme switch to $selected triggered (requires support scripts)"
      fi
    else
      notify-send "No HyDE themes found in $THEME_DIR"
    fi
    ;;

  *)
    usage
    ;;
esac
