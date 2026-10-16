rm -f $out/bin/dsh
# @NODEJS@ is the official Node build (nodejs-official.nix); it needs the store
# libstdc++/glibc on LD_LIBRARY_PATH, and every child the harness spawns through
# process.execPath inherits it from here.
makeWrapper @NODEJS@ $out/bin/dsh \
  --add-flags "--expose-internals $out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js" \
  --prefix LD_LIBRARY_PATH : @NODELIB@

# The model-facing file-search tool is backed by the packaged
# @vscode/ripgrep binary (never GNU grep), but upstream exposes it under
# the name "grep". Rename it to "rg" so the toolset advertises what it
# actually runs. The client bundles key their search-card rendering off
# the same name, so patch them in lockstep. Drop once upstream renames it.
#
# 0.2.0-rc.2 moved the client half from dsh-client-connection (the old
# `case "grep":` / `toolTurn(67, "grep",` / `title: \`Grep ` anchors are all
# gone there) into dsh-client-ui-tool: same literals, but as tool-name
# comparisons, the SEARCH_TITLE_KEYS map and the toolview slot key. The
# displayed title is localized now (tool.title.grep), so the English locale
# value in dsh-client-ui-conversation carries the old Grep -> Search rename.
search_pkg="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"
sed -i \
  -e 's/name: "grep"/name: "rg"/' \
  -e 's/name: "tool:grep"/name: "tool:rg"/' \
  -e 's/Use the grep tool/Use the rg tool/' \
  -e 's/runRipgrep(ctx, exec, "grep"/runRipgrep(ctx, exec, "rg"/' \
  -e 's/"grep-results.txt"/"rg-results.txt"/' \
  "$search_pkg/dsh-tool-fs-search/lib/index.js"
sed -i \
  -e 's/call\.name === "grep"/call.name === "rg"/g' \
  -e 's/call\.name !== "grep"/call.name !== "rg"/g' \
  -e 's/tool === "grep"/tool === "rg"/' \
  -e 's/toolName === "grep"/toolName === "rg"/' \
  -e 's/SEARCH_TITLE_KEYS\.grep/SEARCH_TITLE_KEYS.rg/' \
  -e 's/grep: "tool\.title\.grep"/rg: "tool.title.grep"/' \
  -e 's/key: "grep"/key: "rg"/' \
  "$search_pkg/dsh-client-ui-tool/lib/client.js"
sed -i 's/name === "grep"/name === "rg"/' \
  "$search_pkg/dsh-client-ui-chat/lib/client.js"
sed -i 's/"tool\.title\.grep": "Grep"/"tool.title.grep": "Search"/' \
  "$search_pkg/dsh-client-ui-conversation/lib/client.js"

# Row-id collision with the third-party dsh-file-upload plugin. Upstream
# 0.1.5-rc.1 added its own attachment row `file-upload` to the web-app
# bundle (@deepseek-ai/dsh-client-file-upload — the transport the
# Conversation client's required `fileUpload` inject resolves against),
# and dsh-file-upload's own bundle patch inserts the same id. Two bundles
# inserting one id is fatal before any profile patch applies:
# "duplicate loader entry id: file-upload" on every boot. Rename the
# upstream row: ids are tree-node names, and nothing resolves by this one
# (the client injects the service name, not the row id).
webapp_patch="$search_pkg/dsh-web-app/cordis.patch.yml"
if [ "$(grep -c '^    - id: file-upload$' "$webapp_patch")" != 1 ]; then
  echo "dsh: expected exactly one 'file-upload' row in dsh-web-app — upstream drift" >&2
  exit 1
fi
sed -i 's/^    - id: file-upload$/    - id: file-upload-transport/' "$webapp_patch"
if [ "$(grep -c '^    - id: file-upload-transport$' "$webapp_patch")" != 1 ]; then
  echo "dsh: web-app file-upload row rename failed" >&2
  exit 1
fi

# dsh-widgets server patches (exact-string + count-asserted, fails the
# build loudly on dsh version drift): subagent model override param
# (delegate to deepseek-flash etc. per call) + presentationMeta on the
# subagent / workflow / ralph tools so their persisted tool/result meta
# carries a structured descriptor, and Session.append() accepts
# { ignorable: true } for plugin events (bash_live) so they stop killing
# sessions (see packages/dsh/patch-widgets.py).
PYTHONPATH=@PATCHLIB_DIR@ python3 @PY@ "$search_pkg"

# Session history: released v0 (0.1.1) wrote an obsolete `origin` member in
# `permission/preset` events, and 0.1.5's frozen v0 inventory refuses it, so
# pre-upgrade sessions fail to open ("Failed to load history: ... refuses
# this format v0 Session"). The patcher strips the member while migrating
# (exact-string + count-asserted, see packages/dsh/patch-session-format.py).
PYTHONPATH=@PATCHLIB_DIR@ python3 @PY_V2@ "$search_pkg"

# Session migration v3->v4: 0.1.x marks a steering restart by splicing a
# next-turn message and opening turn/N+1 without a turn/end for turn/N. The
# migration's interrupted-restart repair must keep its splice flag across the
# events that settle the aborted turn, or it skips the synthetic turn/end and
# the transformed artifact is refused ("turn/start does not open the expected
# turn"), which blocked session search entirely (exact-string + count-asserted,
# see packages/dsh/patch-session-migration.py).
PYTHONPATH=@PATCHLIB_DIR@ python3 @PY_MIG@ "$search_pkg"

# run_code / PTC workers: the node runtime tombstones every ambient env key
# except STARTUP_ENVIRONMENT_NAMES, which silently drops LD_LIBRARY_PATH and
# kills the official Node build (no RPATH) with exit 127 before it boots
# (see packages/dsh/patch-ptc-env.py).
PYTHONPATH=@PATCHLIB_DIR@ python3 @PY_PTC@ "$search_pkg"

# Agent presets are declarative rows in 0.2.0-rc.2 (and since 0.1.7): the
# shipped ones are `presets/<id>.patch.yml` files of the dsh-web-app bundle,
# listed in that package's `dsh.bundle.patch`, and a preset is created or
# changed by a patch that declares its row (`- insert: [{id: preset-<id>,
# name: '@deepseek-ai/dsh-agent-preset', config: {...}}]`). The old
# `$DSH_HOME/.agent-presets/<id>/` directories — where this deployment kept
# `neg` and `fast` — are dead: nothing reads them. The two former post-install
# steps are gone with them:
#   * `rm -rf presets/standard` — hiding a shipped preset is now a profile
#     patch (`- id: preset-standard` + `disabled: true`), and the tui profile
#     declares its own presets instead of inheriting the web-app ones;
#   * patch-preset-names.py — the client ships an English copy of the preset
#     names/descriptions (`en` next to `zh` in dsh-client-ui-agent-preset), so
#     there is no Chinese UI copy left to rewrite.
#
# The `neg`/`fast` declarations live in the repo's profile patch layers — see
# modules/user/nix-maid/apps/dsh-tui-preset-patch.py and dsh.nix.
