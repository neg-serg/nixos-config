set -eu
export PATH=/run/current-system/sw/bin:$PATH
# The martty profile: dsh-base + Martty (the upstream terminal UI, the renamed
# @openma/deepseek-harness-tui). Kept in a profile of its own so the trial runs
# side by side with the tui profile (Tianshu) and neither can break the other.
PROFILE_DIR="@homeDir@/.dsh/profiles/martty"
MARTTY_WANT=0.2.39

# `dsh plugin add` initializes the profile directory itself; an existing (even
# empty) directory is enough for the first run. Not `exit 0` when missing — the
# profile is created here, unlike the tui profile which the user installs by
# hand once.
mkdir -p "$PROFILE_DIR"

# pnpm cannot write nested node_modules through the @deepseek-ai store symlink
# (read-only /nix/store), and a fresh `dsh plugin add` re-links the tree: park
# the symlink for the duration of the pnpm operations and let the relink below
# restore it.
PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
if [ -L "$PROFILE_AI" ]; then
  mv "$PROFILE_AI" "$PROFILE_AI.parked"
fi

PKG="$PROFILE_DIR/node_modules/martty/package.json"
VER=""
if [ -f "$PKG" ]; then
  VER="$(jq -r '.version // "0.0.0"' "$PKG")"
fi
if [ -z "$VER" ] || [ "$(printf '%s\n%s\n' "$MARTTY_WANT" "$VER" | sort -V | head -1)" != "$MARTTY_WANT" ]; then
  echo "dsh-martty-ensure: installing martty ^$MARTTY_WANT (current: ${VER:-missing})..."
  (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile martty add "martty@^$MARTTY_WANT" -w) \
    || echo "dsh-martty-ensure: install failed — will retry on next login" >&2
fi

# dsh-free-search: keyless search engines (ddg/bing/...), platform search,
# `web_fetch`. The shipped `deepseek-official` provider answers with an empty
# body from this region, so the profile rows below point the harness `web` row
# at this plugin's `ddg` provider — same contract as the tui profile.
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
  echo "dsh-martty-ensure: installing dsh-free-search ^$FS_WANT (keyless web search)..."
  (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile martty add "dsh-free-search@^$FS_WANT" -w) \
    || echo "dsh-martty-ensure: dsh-free-search install failed — will retry on next login" >&2
fi

# the parked symlink is superseded by the relink below
rm -rf "$PROFILE_AI.parked"

# The profile's @deepseek-ai tree must BE the harness tree: the seeded plugins
# import the harness packages (`@deepseek-ai/dsh-llm`, `@deepseek-ai/dsh-tools`)
# and the host must see one instance per package, not a pnpm peer copy. Same
# relink the tui profile does for the same reason.
HARNESS_AI="@dsh@/lib/node_modules/@deepseek-ai"
AI="$PROFILE_DIR/node_modules/@deepseek-ai"
if [ -d "$HARNESS_AI" ] && { [ ! -L "$AI" ] || [ "$(readlink "$AI")" != "$HARNESS_AI" ]; }; then
  rm -rf "$AI"
  ln -s "$HARNESS_AI" "$AI"
  echo "dsh-martty-ensure: linked the profile @deepseek-ai to the harness tree"
fi

# The profile ships `cordis.patch.yml` as an empty list; rows must replace that
# `[]` (a second YAML root node is a parse error). The martty marker prefix
# keeps this profile's blocks separate from the tui profile's.
PATCH="$PROFILE_DIR/cordis.patch.yml"
if [ -f "$PATCH" ]; then
  ROWS="$(mktemp)"
  printf '%s\n' @pluginRows@ > "$ROWS"
  if fs_ok; then
    printf '%s\n' @searchRows@ >> "$ROWS"
  fi
  python3 @presetPatch@ "$PATCH" "$ROWS" dsh-martty-ensure \
    || echo "dsh-martty-ensure: preset patch failed" >&2
  rm -f "$ROWS"
fi

# The seeded plugins (roster) and the three the default preset mounts
# (dsh-advisor, dsh-category-skill-reminder, dsh-ttsr) live in the repo, not in
# node_modules: copy-if-missing, the same contract the web-profile modules use,
# so local tweaks survive.
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
seed_pkg() {
  name="$1"
  src="$2"
  [ -d "$src" ] || {
    echo "dsh-martty-ensure: $name missing in the repo" >&2
    return 0
  }
  [ -e "$PROFILE_DIR/node_modules/$name" ] && return 0
  mkdir -p "$PROFILE_DIR/node_modules/$name"
  cp -f "$src/package.json" "$PROFILE_DIR/node_modules/$name/package.json" 2> /dev/null || true
  cp -rf "$src/lib" "$PROFILE_DIR/node_modules/$name/lib"
  echo "dsh-martty-ensure: seeded $name"
}
# Path interpolation (not toString): it registers each plugin directory as a
# build input, so the store copy exists even for plugins no other module
# references (a toString-only string leaves the path outside the closure and
# seed_pkg then reports it missing).
@pluginSeeds@
seed "@advisor@" dsh-advisor package.json lib/index.js
seed "@categoryPlugin@" dsh-category-skill-reminder package.json lib/index.js
seed "@ttsr@" dsh-ttsr package.json lib/index.js lib/rules.json
