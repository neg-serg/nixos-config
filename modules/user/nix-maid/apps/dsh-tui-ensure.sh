set -eu
export PATH=/run/current-system/sw/bin:$PATH

# XDG relocation first (idempotent): it must run before the profile checks, so
# a machine with the legacy ~/.dsh still ends up on the XDG layout. Failure is
# not fatal — the legacy paths below keep working through the compat symlinks.
if [ -x "@xdgMigrate@" ]; then
  "@xdgMigrate@" || echo "dsh-tui-ensure: dsh-xdg-migrate reported a problem — keeping legacy paths"
fi

PROFILE_DIR="@homeDir@/.dsh/profiles/tui"
[ -d "$PROFILE_DIR" ] || exit 0

# The profile runs dsh-TUI (@deepseek-harness-tui/dsh-tui), the Cordis terminal
# front door over dsh-base.
#
# Profiles on this host used to link node_modules/@deepseek-ai to the harness
# tree, because an older plugin pulled in its own peer copies and those broke
# the preset mount. dsh-TUI does not need that link — the harness packages are
# peers of the bundle and dsh's own profile module fallback resolves them — and
# the link actively breaks it: the fallback creates its links under
# node_modules/@deepseek-ai, which through a store symlink is read-only
# (EROFS at every start). So a leftover link is removed instead of re-created.
PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
if [ -L "$PROFILE_AI" ]; then
  rm -f "$PROFILE_AI"
  echo "dsh-tui-ensure: removed the legacy @deepseek-ai store link (dsh owns the module fallback now)"
fi

# The profile manifest is the owning package.json of the modules the preset
# rows mount by a *relative* path (the neg preset's tool-bootstrap.mjs, copied
# below), and the harness's package inventory reads that owner for the
# dsh_plugin_packages request field. A manifest that declares a name without a
# version is rejected there — and that rejection is not scoped to the plugin:
# every DeepSeek request of every session dies before its HTTP dispatch with
# "DeepSeek request extension preparation failed" (REQUEST_EXTENSION). The
# manifest is created by hand once (dsh's own profile templates omit the
# field), so the version is kept here.
MANIFEST="$PROFILE_DIR/package.json"
if [ -f "$MANIFEST" ] && [ "$(jq -r '.version // ""' "$MANIFEST" 2> /dev/null)" = "" ]; then
  tmp="$(mktemp)"
  if jq --indent 2 '. + { version: "0.0.0" }' "$MANIFEST" > "$tmp"; then
    chmod 600 "$tmp"
    mv "$tmp" "$MANIFEST"
    echo "dsh-tui-ensure: $MANIFEST: added the missing version (the harness rejects a versionless profile manifest)"
  else
    rm -f "$tmp"
    echo "dsh-tui-ensure: could not add a version to $MANIFEST" >&2
  fi
fi

# The retired preset root. Until dsh 0.1.6 the harness discovered presets as
# $DSH_HOME/.agent-presets/<id>/{preset.yml,agent.cordis.yml} and the two preset
# modules (dsh-fast.nix, dsh-liangshen-fork.nix — both retired with the 0.2.0
# upgrade) synced `neg` and `fast` there. The 0.2.0 registry reads declaration
# rows only (see dsh-presets.nix), so the directory is dead weight: drop it once
# and say so; the repo directories stay the source of truth for the declarations.
# Version policy for the two profile plugins: follow the registry's `latest`
# dist-tag instead of a floor written here. The floor form (">= 0.14.0") only
# ever moved the profile once: `^0.14.0` caps below 0.15, so a 0.15 release
# would sit unused forever, and pnpm's minimumReleaseAge holds fresh releases
# unless the package is excluded (pnpm writes that exclusion itself when it
# installs). `latest` is upstream's own channel, so withdrawn releases stay out
# of the way: 0.14.1 is published but deprecated ("please use 0.14.0") and
# untagged, which is exactly what asking for `latest` rather than the highest
# published version gives us. No downgrades — only a strictly newer version
# replaces what is installed. The registry answers directly on this host; the
# SOCKS proxy is the fallback (same shape as dsh-desktop.nix).
registry_version() {
  pkg="$1"
  out="$(curl -fsSL --max-time 20 "https://registry.npmjs.org/$pkg/latest" 2> /dev/null || true)"
  if [ -z "$out" ]; then
    out="$(curl -fsSL --max-time 20 --proxy socks5h://127.0.0.1:10808 "https://registry.npmjs.org/$pkg/latest" 2> /dev/null || true)"
  fi
  printf '%s' "$out" | jq -r '.version // empty' 2> /dev/null || true
}
newer() {
  [ "$1" != "$2" ] || return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

# Install (or re-add) one profile plugin, granting the harness's own
# version-compatibility exemptions when its error text asks for them.
#
# The TUI bundle's cordis.patch.yml still carries two 0.1.5-era rows
# (`dsh-tui-agent-presets` -> @deepseek-ai/dsh-agent-presets and
# `dsh-tui-code-runtime` -> @deepseek-ai/dsh-code-runtime-worker-thread) behind
# `disabled: !!js` guards. The post-install compatibility check collects the
# rows' package names statically — an unevaluated expression is never `true` —
# and denies the WHOLE install when those packages' registry versions only
# peer-depend on 0.1.5 (observed 2026-10-16: every activation/login since 03:24
# failed with "installation rejected", and the TUI session died showing
# "DSH plugin incompatible with dsh version"). A 0.2.x runtime ships the
# replacements and the profile layer disables both rows, so nothing mounts
# them; the harness prints the exact exemption it wants, hence granting what it
# asks for and retrying once instead of hardcoding versions that move with the
# bundle.
install_profile_plugin() {
  spec="$1"
  out="$(mktemp)"
  if (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add "$spec" -w) > "$out" 2>&1; then
    rm -f "$out"
    return 0
  fi
  granted=0
  while read -r package version; do
    [ -n "$package" ] || continue
    echo "dsh-tui-ensure: granting the harness exemption $package on $version"
    dsh plugin --profile tui allow-version "$package" --dsh-version "$version" --accept-risk > /dev/null 2>&1 || true
    granted=1
  done < <(sed -n 's/.*dsh plugin --profile tui allow-version \([^ ]*\) --dsh-version \([^ ]*\).*/\1 \2/p' "$out" | sort -u)
  if [ "$granted" -eq 0 ]; then
    cat "$out" >&2
    rm -f "$out"
    return 1
  fi
  if (cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add "$spec" -w) >> "$out" 2>&1; then
    rm -f "$out"
    return 0
  fi
  cat "$out" >&2
  rm -f "$out"
  return 1
}

LEGACY_PRESETS="@homeDir@/.dsh/.agent-presets"
if [ -d "$LEGACY_PRESETS" ]; then
  rm -rf "$LEGACY_PRESETS"
  echo "dsh-tui-ensure: removed the retired $LEGACY_PRESETS (0.2.0 reads preset declarations, not directories)"
fi

PKG="$PROFILE_DIR/node_modules/@deepseek-harness-tui/dsh-tui/package.json"
VER=""
if [ -f "$PKG" ]; then
  VER="$(jq -r '.version // "0.0.0"' "$PKG")"
fi
TUI_WANT="$(registry_version '@deepseek-harness-tui%2Fdsh-tui')"
if [ -z "$VER" ] || { [ -n "$TUI_WANT" ] && newer "$VER" "$TUI_WANT"; }; then
  if [ -z "$TUI_WANT" ]; then
    echo "dsh-tui-ensure: registry lookup for @deepseek-harness-tui/dsh-tui failed — keeping ${VER:-nothing}" >&2
  else
    echo "dsh-tui-ensure: installing @deepseek-harness-tui/dsh-tui ^$TUI_WANT (current: ${VER:-missing})..."
    install_profile_plugin "@deepseek-harness-tui/dsh-tui@^$TUI_WANT" \
      || echo "dsh-tui-ensure: install failed — will retry on next login" >&2
  fi
fi

# The dsh-TUI bundle's liangshen preset still carries the 0.1.x
# `@deepseek-ai/dsh-workflow-worker-thread` row beside its 0.2.0 replacement
# `@deepseek-ai/dsh-workflow-ptc`, guarded by an unevaluated `disabled: !!js`
# expression. The harness's compatibility preflight reads the declaration
# statically — an expression never equals `true` — so it denies that row and
# then the whole `liangshen-plugins` Include that reaches it: the bundled
# preset cannot mount and every boot prints two ~700-character warnings. On a
# runtime that ships the replacement the guarded row is dead either way, so it
# is pruned from the installed copy; the install above is what puts it back.
# A pre-rename runtime keeps it — there the fallback is the live provider.
LIANGSHEN_PRESET="$PROFILE_DIR/node_modules/@deepseek-harness-tui/dsh-tui/presets/liangshen/agent.cordis.yml"
DSH_RUNTIME="$(dsh --version 2> /dev/null | head -1 || true)"
case "$DSH_RUNTIME" in
  "" | 0.0.* | 0.1.*) ;;
  *)
    if [ -f "$LIANGSHEN_PRESET" ]; then
      python3 @liangshenPrune@ "$LIANGSHEN_PRESET" \
        || echo "dsh-tui-ensure: liangshen row prune failed" >&2
    fi
    ;;
esac

# dsh-free-search: keyless search engines (ddg/bing/...), platform search,
# `web_fetch`. The shipped `deepseek-official` provider answers with an empty
# body from this region, so the profile rows below ask for this plugin's `ddg`
# engine. 0.8.1 was the first release whose peers cover the 0.2.0 harness; the
# version now follows the registry like the TUI does, and 0.8.1+ dropped the
# `web.searchProvider` override this profile used to write — see the searchRows
# commentary.
FS_PKG="$PROFILE_DIR/node_modules/dsh-free-search/package.json"
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
FS_WANT="$(registry_version dsh-free-search)"
if ! fs_ok || { [ -n "$FS_WANT" ] && newer "$FS_HAVE" "$FS_WANT"; }; then
  if [ -z "$FS_WANT" ]; then
    echo "dsh-tui-ensure: registry lookup for dsh-free-search failed — keeping ${FS_HAVE:-nothing}" >&2
  else
    echo "dsh-tui-ensure: installing dsh-free-search ^$FS_WANT (keyless web search)..."
    install_profile_plugin "dsh-free-search@^$FS_WANT" \
      || echo "dsh-tui-ensure: dsh-free-search install failed — will retry on next login" >&2
  fi
fi

# dsh-find-plugin: plugin discovery from inside the session (`find_dsh_plugin`
# searches the dsh-plugin topic live, ranks by stars and returns a ready
# `dsh plugin add` command). The package ships its own bundle patch, so unlike
# the repo-seeded plugins it owes no loader row here — the caretaker only keeps
# the package installed. install_profile_plugin grants the version exemption it
# needs: the plugin's declared peer range stops at 0.1.7, so the 0.2.0 harness
# asks for an exact-version exemption on 0.2.0-rc.2 (the harness prints it).
FP_PKG="$PROFILE_DIR/node_modules/dsh-find-plugin/package.json"
fp_ok() {
  [ -f "$FP_PKG" ] || return 1
  [ "$(jq -r '.dependencies["dsh-find-plugin"] // ""' "$PROFILE_DIR/package.json")" != "" ] || return 1
  return 0
}
FP_HAVE=""
if [ -f "$FP_PKG" ]; then
  FP_HAVE="$(jq -r '.version // ""' "$FP_PKG")"
fi
FP_WANT="$(registry_version dsh-find-plugin)"
if ! fp_ok || { [ -n "$FP_WANT" ] && newer "$FP_HAVE" "$FP_WANT"; }; then
  if [ -z "$FP_WANT" ]; then
    echo "dsh-tui-ensure: registry lookup for dsh-find-plugin failed — keeping ${FP_HAVE:-nothing}" >&2
  else
    echo "dsh-tui-ensure: installing dsh-find-plugin ^$FP_WANT (in-session plugin discovery)..."
    install_profile_plugin "dsh-find-plugin@^$FP_WANT" \
      || echo "dsh-tui-ensure: dsh-find-plugin install failed — will retry on next login" >&2
  fi
fi

# dsh-TUI session visibility: the 0.10.x hasPrompt carry-forward defect (a
# session indexed while its log was a stub stayed hasPrompt = false forever and
# disappeared from the conversations list) is fixed upstream in 0.14.0 — the
# append-growth path now derives the flag from the log suffix and ORs it with
# the carried one (`hasPrompt: previous.hasPrompt || suffix.hasHumanPrompt`),
# and an unreadable log is listed (`derived?.hasPrompt ?? true`). The patcher
# that rewrote the installed list.js is retired with it.

PATCH="$PROFILE_DIR/cordis.patch.yml"
if [ -f "$PATCH" ]; then
  ROWS="$(mktemp)"
  printf '%s\n' @pluginRows@ > "$ROWS"
  if fs_ok; then
    printf '%s\n' @searchRows@ >> "$ROWS"
  fi
  # Provider rows (currently the llm-deepseek retry policy — see llmRows in
  # dsh-terminal-plugins.nix). Unconditional: the rows target entries the base
  # bundle always mounts, so a missing plugin cannot make them dangling.
  printf '%s\n' @llmRows@ >> "$ROWS"
  # Files the preset declarations reference by a *relative* path: inserted rows
  # anchor relative paths beside their patch file, i.e. this profile directory.
  # Today that is the neg preset's tool-bootstrap.mjs; the repo copy is the
  # source of truth, so it is refreshed on every login like the theme.
  while IFS=$'\t' read -r src name; do
    [ -n "$src" ] || continue
    cp -f "$src" "$PROFILE_DIR/$name"
  done < <(jq -r '.presets[].sidecars[] | "\(.src)\t\(.name)"' @presetData@ 2> /dev/null)
  # The rewriter owns the fallback-preset row (the scoped id dsh-TUI's bundle
  # exposes), the agent-preset declarations and the plugin rows; see its header
  # for the retired code-runtime block it also consumes.
  python3 @presetPatch@ "$PATCH" "$ROWS" @presetData@ dsh-tui-ensure \
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
#
# "Seeded" is judged per file, not per directory. pnpm's hoisted-linker
# reconciliation rewrites the whole node_modules tree and drops files it does
# not own, so a seeded package can lose its manifest while its lib/ stays:
# observed 2026-10-14 on dsh-agent-usage-reminder, whose directory survived
# without package.json — the harness then could not resolve the row as a
# package and every boot printed "dsh-agent-usage-reminder: failed to import"
# with the plugin silently inert. A directory-only check skipped the repair
# forever, because the directory was there. An existing file is never
# overwritten, so local edits survive.
seed_pkg() {
  name="$1"
  src="$2"
  dir="$PROFILE_DIR/node_modules/$name"
  [ -d "$src" ] || {
    echo "dsh-tui-ensure: $name missing in the repo" >&2
    return 0
  }
  [ -f "$dir/package.json" ] && [ -f "$dir/lib/index.js" ] && return 0
  mkdir -p "$dir"
  [ -f "$dir/package.json" ] || cp -f "$src/package.json" "$dir/package.json" 2> /dev/null || true
  [ -d "$dir/lib" ] || cp -rf "$src/lib" "$dir/lib"
  echo "dsh-tui-ensure: seeded $name (repaired $dir)"
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
# ~/.dsh-tui/{theme,lang}.json. The repo copy is the theme's source of truth
# (like the presets), but the chosen theme and language are the user's — seed
# each preference only while it is unset, so /theme and /lang survive a rebuild.
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
