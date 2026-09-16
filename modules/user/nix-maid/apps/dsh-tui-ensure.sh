set -eu
export PATH=/run/current-system/sw/bin:$PATH
PROFILE_DIR="@homeDir@/.dsh/profiles/tui"
[ -d "$PROFILE_DIR" ] || exit 0

# The profile runs dsh-TUI (@deepseek-harness-tui/dsh-tui), the Cordis terminal
# front door. It replaced Tianshu (@huiliyi37/dsh-tianshu-tui) in 2026-09.
#
# The Tianshu era needed the profile's @deepseek-ai tree linked to the harness
# tree: pnpm installed the plugin's own peer copies (0.1.2-rc.x), and those ship
# an older agent-presets schema, so the shipped `standard` preset failed to
# mount. dsh-TUI does not need that link — the harness packages are peers of
# the bundle and dsh's own profile module fallback resolves them — and the link
# actively breaks it: the healer creates its links under
# node_modules/@deepseek-ai, which through a store symlink is read-only
# (EROFS at every start). So a leftover link is removed instead of re-created.
PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
if [ -L "$PROFILE_AI" ]; then
  rm -f "$PROFILE_AI"
  echo "dsh-tui-ensure: removed the legacy @deepseek-ai store link (dsh owns the module fallback now)"
fi

PKG="$PROFILE_DIR/node_modules/@deepseek-harness-tui/dsh-tui/package.json"
VER=""
if [ -f "$PKG" ]; then
  VER="$(jq -r '.version // "0.0.0"' "$PKG")"
fi
if [ -z "$VER" ] || [ "$(printf '%s\n%s\n' 0.10.1 "$VER" | sort -V | head -1)" != "0.10.1" ]; then
  echo "dsh-tui-ensure: installing @deepseek-harness-tui/dsh-tui ^0.10.1 (current: ${VER:-missing})..."
  (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add '@deepseek-harness-tui/dsh-tui@^0.10.1' -w) \
    || echo "dsh-tui-ensure: install failed — will retry on next login" >&2
fi

# dsh-free-search: keyless search engines (ddg/bing/...), platform search,
# `web_fetch`. The shipped `deepseek-official` provider answers with an empty
# body from this region, so the profile rows below point the harness `web`
# row at this plugin's `ddg` provider. 0.4.24 is the first release on the
# 0.1.5 settings API.
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

PATCH="$PROFILE_DIR/cordis.patch.yml"
if [ -f "$PATCH" ]; then
  ROWS="$(mktemp)"
  printf '%s\n' @pluginRows@ > "$ROWS"
  if fs_ok; then
    printf '%s\n' @searchRows@ >> "$ROWS"
  fi
  # dsh-TUI's bundle patch owns the agent-preset roster under the scoped
  # `dsh-tui-agent-presets` id (the base `agent-presets` row is gone), and it
  # already inserts a code-runtime row — a second one is a duplicate
  # `codeRuntime` registration and kills the boot. Both facts are parameters:
  # `<prefix> <preset-row-id> <no-runtime|runtime>`.
  python3 @presetPatch@ "$PATCH" "$ROWS" dsh-tui-ensure dsh-tui-agent-presets no-runtime \
    || echo "dsh-tui-ensure: preset patch failed" >&2
  rm -f "$ROWS"
fi

# The profile fallback preset (settings.yaml still wins) mounts three repo-local
# plugins that the web profile seeds through their own modules; without copies
# here the preset aborts with "rows name plugins that cannot be resolved".
# Copy-if-missing, the same contract those modules use, so local tweaks survive.
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

# Theme and language. dsh-TUI discovers user themes as
# ~/.dsh-tui/themes/<name>.json and persists the choices in
# ~/.dsh-tui/{theme,lang}.json; Tianshu's prefs.json is not read. The repo copy
# is the theme's source of truth (like the presets), but the chosen theme and
# language are the user's — seed each preference only while it is unset, so
# /theme and /lang survive a rebuild.
TUI_DIR="@homeDir@/.dsh-tui"
mkdir -p "$TUI_DIR/themes"
cp -f "@themeJson@" "$TUI_DIR/themes/neg.json"
for pref in theme:neg lang:en; do
  key="${pref%%:*}"
  value="${pref##*:}"
  file="$TUI_DIR/$key.json"
  if [ ! -f "$file" ] || [ "$(jq -r --arg k "$key" '.[$k] // ""' "$file" 2> /dev/null)" = "" ]; then
    printf '{\n  "%s": "%s"\n}\n' "$key" "$value" > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "dsh-tui-ensure: seeded $key=$value"
  fi
done
