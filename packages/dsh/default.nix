{
  lib,
  fetchurl,
  python3,
  makeWrapper,
  nodejs,
  buildNpmPackage,
  runCommand,
}:
let
  version = "0.1.5-rc.1";

  tarball = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-Gnlxnxx2ORisMOgZTfeDqTMMaxLV8EyVBzGj+KHD2dA=";
  };

  # Registry tarballs ship no lockfile; npm ci needs one.
  #
  # The published package.json declares devDependencies on internal
  # prereleases that are not on the registry at all
  # (@deepseek-ai/dsh-experimental-code-runtime-python@^0.1.5-rc.1 -> 404),
  # and npm resolves devDependencies before honouring --omit=dev, so `npm ci`
  # cannot run against the shipped package.json. dsh ships prebuilt lib/ and
  # never runs its dev tooling in this build, so devDependencies are dropped
  # here and in the lockfile (generated the same way).
  src = runCommand "dsh-src" { nativeBuildInputs = [ python3 ]; } ''
        mkdir -p $out
        tar xzf ${tarball} -C $out --strip-components=1
        cp ${./package-lock.json} $out/package-lock.json
        python3 - "$out/package.json" <<'PY'
    import json
    import sys

    path = sys.argv[1]
    pkg = json.load(open(path))
    pkg.pop("devDependencies", None)
    json.dump(pkg, open(path, "w"), indent=2, ensure_ascii=False)
    PY
  '';
in
buildNpmPackage {
  pname = "dsh";
  inherit version src;

  # dsh ships prebuilt lib/; its package.json has no build script.
  dontNpmBuild = true;

  nativeBuildInputs = [
    python3 # node-gyp compiles native deps (node-pty) during npm rebuild
    makeWrapper # rewrap the dsh launcher with node --expose-internals (HMR)
  ];

  # The HMR plugin requires node --expose-internals, which the default wrapper
  # omits. Rewrap the launcher the same way the dsh systemd service does.
  postInstall = ''
    rm -f $out/bin/dsh
    makeWrapper ${lib.getExe nodejs} $out/bin/dsh \
      --add-flags "--expose-internals $out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"

    # The model-facing file-search tool is backed by the packaged
    # @vscode/ripgrep binary (never GNU grep), but upstream exposes it under
    # the name "grep". Rename it to "rg" so the toolset advertises what it
    # actually runs. The client bundles key their search-card rendering off
    # the same name, so patch them in lockstep. Drop once upstream renames it.
    search_pkg="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"
    sed -i \
      -e 's/name: "grep"/name: "rg"/' \
      -e 's/name: "tool:grep"/name: "tool:rg"/' \
      -e 's/Use the grep tool/Use the rg tool/' \
      -e 's/runRipgrep(ctx, exec, "grep"/runRipgrep(ctx, exec, "rg"/' \
      -e 's/"grep-results.txt"/"rg-results.txt"/' \
      "$search_pkg/dsh-tool-fs-search/lib/index.js"
    sed -i 's/key: "grep"/key: "rg"/' \
      "$search_pkg/dsh-client-ui-tool/lib/client.js"
    sed -i \
      -e 's/case "grep":/case "rg":/' \
      -e 's/if (name === "grep")/if (name === "rg")/' \
      -e 's/toolTurn(67, "grep",/toolTurn(67, "rg",/' \
      -e 's/title: `Grep /title: `Search /' \
      "$search_pkg/dsh-client-connection/lib/client.js"

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
    # (delegate to deepseek-v4-flash etc. per call) + presentationMeta on the
    # subagent / workflow / ralph tools so their persisted tool/result meta
    # carries a structured descriptor, and Session.append() accepts
    # { ignorable: true } for plugin events (bash_live) so they stop killing
    # sessions (see packages/dsh/patch-widgets.py).
    python3 ${./patch-widgets.py} "$search_pkg"

    # Session history: released v0 (0.1.1) wrote an obsolete `origin` member in
    # `permission/preset` events, and 0.1.5's frozen v0 inventory refuses it, so
    # pre-upgrade sessions fail to open ("Failed to load history: ... refuses
    # this format v0 Session"). The patcher strips the member while migrating
    # (exact-string + count-asserted, see packages/dsh/patch-session-format.py).
    python3 ${./patch-session-format.py} "$search_pkg"

    # Drop the shipped `standard` agent preset from the roster: the user runs
    # the neg preset (liangshen fork) by default (see
    # modules/user/nix-maid/apps/dsh-liangshen-fork.nix) and asked for the
    # standard entry to be removed from the picker. 0.1.5-rc.1 moved the
    # presets out of dsh's own config/ into the @deepseek-ai/dsh-agent-presets
    # dependency, whose `presets/` dir is the shipped preset root; removing the
    # subdir hides the preset at discovery.
    presets="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-presets/presets"
    rm -rf "$presets/standard"

    # The shipped preset.yml names/descriptions are Chinese (PTC 模式 / 极简模式
    # / 创造模式); the user's de-Chinese rule covers UI copy, and the picker and
    # /mode render these. Exact-match + count-asserted (see patch-preset-names.py).
    python3 ${./patch-preset-names.py} "$presets"
  '';

  # Prefetched dependency tree; hash from `prefetch-npm-deps package-lock.json`
  npmDepsHash = "sha256-cqN2pdqnxEqJ/dPKW/cNSLICI4kB6qSJ7PqKqsQAMRo=";

  meta = with lib; {
    description = "DeepSeek Harness (dsh) — open-source agent harness, everything is a plugin";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dsh";
    maintainers = [ ];
  };
}
