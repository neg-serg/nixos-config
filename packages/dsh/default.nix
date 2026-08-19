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
  version = "0.1.0-rc.6";

  tarball = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-G4qaCtPH/q7OR5JuC9N8oVHHzPqZeVOvpf0BJheE6tw=";
  };

  # Registry tarballs ship no lockfile; npm ci needs one.
  src = runCommand "dsh-src" { } ''
    mkdir -p $out
    tar xzf ${tarball} -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
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

    # dsh-widgets server patches (exact-string + count-asserted, fails the
    # build loudly on dsh version drift): subagent model override param
    # (delegate to deepseek-v4-flash etc. per call) + presentationMeta on the
    # subagent / workflow / ralph tools so their persisted tool/result meta
    # carries a structured descriptor, and Session.append() accepts
    # { ignorable: true } for plugin events (bash_live) so they stop killing
    # sessions (see packages/dsh/patch-widgets.py).
    python3 ${./patch-widgets.py} "$search_pkg"

    # Drop the shipped `standard` agent preset from the roster: the user runs
    # the neg preset (liangshen fork) by default (see
    # modules/user/nix-maid/apps/dsh-liangshen-fork.nix) and asked for the
    # standard entry to be removed from the picker. SHIPPED_PRESET_ROOT is
    # this config dir, so removing the subdir hides the preset at discovery.
    rm -rf "$out/lib/node_modules/@deepseek-ai/dsh/config/agent-presets/standard"

    # The shipped preset.yml names/descriptions are Chinese (PTC 模式 / 极简模式
    # / 创造模式); the user's de-Chinese rule covers UI copy, and the picker and
    # /mode render these. Exact-match + count-asserted (see patch-preset-names.py).
    python3 ${./patch-preset-names.py} "$out/lib/node_modules/@deepseek-ai/dsh"
  '';

  # Prefetched dependency tree; hash from `prefetch-npm-deps package-lock.json`
  npmDepsHash = "sha256-9Cx3OhIK3xuyd6o+HZhAs+2eGsIrys8fNdtRePd4GnQ=";

  meta = with lib; {
    description = "DeepSeek Harness (dsh) — open-source agent harness, everything is a plugin";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dsh";
    maintainers = [ ];
  };
}
