WALLPAPER_SRC=""

# Source 1: quickshell wallpaper path file (most up-to-date)
qs_notify="@mainHome@/.cache/quickshell-wallpaper-path"
if [ -f "$qs_notify" ]; then
  candidate="$(head -1 "$qs_notify" 2> /dev/null || true)"
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    WALLPAPER_SRC="$candidate"
  fi
fi

# Source 2: wl daemon state (current wallpaper from last session)
if [ -z "$WALLPAPER_SRC" ]; then
  wl_state="@mainHome@/.local/state/wl/state.json"
  if [ -f "$wl_state" ]; then
    candidate="$(@jq@ -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$wl_state" 2> /dev/null || true)"
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      WALLPAPER_SRC="$candidate"
    fi
  fi
fi

# Source 3: first image from the wl wallpaper directory
if [ -z "$WALLPAPER_SRC" ]; then
  candidate="$(find @mainHome@/pic/wl -maxdepth 1 -type f 2> /dev/null | sort -R | head -1 || true)"
  if [ -n "$candidate" ]; then
    WALLPAPER_SRC="$candidate"
  fi
fi

# Source 4: hardcoded fallback
if [ -z "$WALLPAPER_SRC" ]; then
  WALLPAPER_SRC="@greeterWallpaperFallback@"
fi

if [ -f "$WALLPAPER_SRC" ]; then
  install -Dm644 -o greeter -g greeter "$WALLPAPER_SRC" "@greeterWallpaperDst@"
else
  echo "greetd wallpaper: no source found (tried wl state, qs notify, pic/wl/, fallback)" >&2
fi

# Provision the real quickshell theme for the greeter (colors/timings).
# The desktop shell writes Theme/.theme.json into the user's config;
# reuse it so the greeter matches the last session. Fall back to a
# merge of the repo greeter/colors parts (jsonc with full-line //
# comments) when the user theme file does not exist yet.
greeter_theme_src="@mainHome@/.config/quickshell/Theme/.theme.json"
if [ ! -f "$greeter_theme_src" ]; then
  greeter_theme_tmp="$(mktemp)"
  theme_parts="@themeDir@"
  @gnused@/bin/sed -E '/^[[:space:]]*\/\//d' "$theme_parts/greeter.jsonc" > "$greeter_theme_tmp.greeter" || true
  @gnused@/bin/sed -E '/^[[:space:]]*\/\//d' "$theme_parts/colors.jsonc" > "$greeter_theme_tmp.colors" || true
  @jq@ -s 'add' "$greeter_theme_tmp.greeter" "$greeter_theme_tmp.colors" > "$greeter_theme_tmp" 2> /dev/null || rm -f "$greeter_theme_tmp"
  rm -f "$greeter_theme_tmp.greeter" "$greeter_theme_tmp.colors"
  if [ -s "$greeter_theme_tmp" ]; then
    greeter_theme_src="$greeter_theme_tmp"
  fi
fi
if [ -f "$greeter_theme_src" ]; then
  install -Dm644 -o greeter -g greeter "$greeter_theme_src" /home/greeter/.config/quickshell/Theme/.theme.json
fi
