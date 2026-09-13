set -eu
export PATH=/run/current-system/sw/bin:$PATH
PROFILE_DIR="@homeDir@/.dsh/profiles/tui"
[ -d "$PROFILE_DIR" ] || exit 0

# pnpm cannot write nested node_modules through the @deepseek-ai store
# symlink (read-only /nix/store), and a fresh `dsh plugin add` re-links the
# tree: park the symlink for the duration of the pnpm operations and let the
# relink below restore it.
PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
if [ -L "$PROFILE_AI" ]; then
  mv "$PROFILE_AI" "$PROFILE_AI.parked"
fi

PKG="$PROFILE_DIR/node_modules/@huiliyi37/dsh-tianshu-tui/package.json"
VER=""
if [ -f "$PKG" ]; then
  VER="$(jq -r '.version // "0.0.0"' "$PKG")"
fi
if [ -z "$VER" ] || [ "$(printf '%s\n%s\n' 0.1.2-rc.29 "$VER" | sort -V | head -1)" != "0.1.2-rc.29" ]; then
  echo "dsh-tui-ensure: installing dsh-tianshu-tui ^0.1.2-rc.29 (current: ${VER:-missing}; 0.1.5 session API)..."
  (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add '@huiliyi37/dsh-tianshu-tui@^0.1.2-rc.29' -w) \
    || echo "dsh-tui-ensure: install failed — will retry on next login" >&2
fi

# dsh-free-search: keyless search engines (ddg/bing/...), platform search,
# `web_fetch`. The shipped `deepseek-official` provider answers with an empty
# body from this region, so the profile rows below point the harness `web`
# row at this plugin's `ddg` provider. 0.4.24 is the first release on the
# 0.1.5 settings API; the relink further down repairs pnpm's peer copies.
FS_PKG="$PROFILE_DIR/node_modules/dsh-free-search/package.json"
FS_WANT=0.4.24
# Registered means: the package is a profile dependency and its files are
# there. A leftover directory from a half-finished pnpm run is deliberately
# not "installed" — and note that `dsh plugin add` writes the dependency but
# NOT `dsh.profile.bundles`, so the mount below is spelled out as explicit
# rows instead of relying on the plugin's own bundle layer.
fs_ok() {
  [ -f "$FS_PKG" ] || return 1
  [ "$(jq -r '.dependencies["dsh-free-search"] // ""' "$PROFILE_DIR/package.json")" != "" ] || return 1
  return 0
}
FS_HAVE=""
if [ -f "$FS_PKG" ]; then
  FS_HAVE="$(jq -r '.version // ""' "$FS_PKG")"
fi
if ! fs_ok || [ "$(printf '%s\n%s\n' "$FS_WANT" "$FS_HAVE" | sort -V | head -1)" != "$FS_WANT" ]; then
  echo "dsh-tui-ensure: installing dsh-free-search ^$FS_WANT (keyless web search)..."
  (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add "dsh-free-search@^$FS_WANT" -w) \
    || echo "dsh-tui-ensure: dsh-free-search install failed — will retry on next login" >&2
fi

# the parked symlink is superseded by the relink below
rm -rf "$PROFILE_AI.parked"

HARNESS_AI="@dsh@/lib/node_modules/@deepseek-ai"
AI="$PROFILE_DIR/node_modules/@deepseek-ai"
if [ -d "$HARNESS_AI" ] && { [ ! -L "$AI" ] || [ "$(readlink "$AI")" != "$HARNESS_AI" ]; }; then
  rm -rf "$AI"
  ln -s "$HARNESS_AI" "$AI"
  echo "dsh-tui-ensure: linked the profile @deepseek-ai to the harness tree"
fi

PATCH="$PROFILE_DIR/cordis.patch.yml"
if [ -f "$PATCH" ]; then
  ROWS="$(mktemp)"
  printf '%s\n' @pluginRows@ > "$ROWS"
  if fs_ok; then
    printf '%s\n' @searchRows@ >> "$ROWS"
  fi
  python3 @presetPatch@ "$PATCH" "$ROWS" || echo "dsh-tui-ensure: preset patch failed" >&2
  rm -f "$ROWS"
fi

# The neg preset (the TUI default, see below) mounts three repo-local
# plugins that the web profile seeds through their own modules; without
# copies here the preset aborts with "rows name plugins that cannot be
# resolved". Copy-if-missing, the same contract those modules use, so local
# tweaks survive.
seed() {
  src="$1"
  name="$2"
  shift 2
  dir="$PROFILE_DIR/node_modules/$name"
  mkdir -p "$dir/lib"
  for f in "$@"; do
    [ -f "$dir/$f" ] || cp "$src/$f" "$dir/$f"
  done
}
# The user's host/agent plugins (see tuiPlugins): copy-if-missing, the same
# contract their web-profile modules use, so edits in this repo re-apply
# after deleting the profile copy.
seed_pkg() {
  name="$1"
  src="$2"
  [ -d "$src" ] || {
    echo "dsh-tui-ensure: $name missing in the repo" >&2
    return 0
  }
  [ -e "$PROFILE_DIR/node_modules/$name" ] && return 0
  mkdir -p "$PROFILE_DIR/node_modules/$name"
  cp -f "$src/package.json" "$PROFILE_DIR/node_modules/$name/package.json" 2> /dev/null || true
  cp -rf "$src/lib" "$PROFILE_DIR/node_modules/$name/lib"
  echo "dsh-tui-ensure: seeded $name"
}
# Path interpolation (not toString): it registers each plugin directory as a
# build input, so the store copy exists even for plugins no other module
# references (a toString-only string leaves the path outside the closure and
# seed_pkg then reports it missing).
@pluginSeeds@
# The neg preset's own plugins (agent plane, referenced by the preset file).
seed "@advisor@" dsh-advisor package.json lib/index.js
seed "@categoryPlugin@" dsh-category-skill-reminder package.json lib/index.js
seed "@ttsr@" dsh-ttsr package.json lib/index.js lib/rules.json

# Theme: the repo copy is the source of truth (like the presets), but the
# chosen theme in prefs.json is the user's — seed `custom:neg` only while
# no theme is set, so `/theme` choices survive a rebuild.
TUI_THEME_DIR="@homeDir@/.dsh-tui/themes"
mkdir -p "$TUI_THEME_DIR"
cp -f "@themeJson@" "$TUI_THEME_DIR/neg.json"
TUI_PREFS="@homeDir@/.dsh-tui/prefs.json"
if [ -f "$TUI_PREFS" ] && [ "$(jq -r '.theme // ""' "$TUI_PREFS")" = "" ]; then
  jq '.theme = "custom:neg"' "$TUI_PREFS" > "$TUI_PREFS.tmp" && mv "$TUI_PREFS.tmp" "$TUI_PREFS"
  echo "dsh-tui-ensure: seeded the neg theme (custom:neg)"
fi
