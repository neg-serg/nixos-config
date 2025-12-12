{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  bun,
  coreutils,
  pkg-config,
  cargo,
  rustc,
  electron,
  git,
}: let
  version = "2.0.3";
  storeRootName = "awrit";
in
  buildNpmPackage rec {
    pname = storeRootName;
    inherit version;

    src = fetchFromGitHub {
      owner = "chase";
      repo = "awrit";
      rev = "awrit-native-rs-${version}";
      hash = "sha256-SUPzVwtMi+5Jq28KzqjXNWJCZkgk9nHelLvHBh42JVo=";
    };

    npmDepsHash = "sha256-MyBqVdKseKbNfet/b+1TU7YJtHaQbTRY4xYgaqVM3ys=";

    patches = [
      ./fix-config-and-version.patch
    ];

    npmInstallFlags = ["--ignore-scripts"];
    dontNpmBuild = true;

    preConfigure = ''
      export ELECTRON_SKIP_BINARY_DOWNLOAD=1
      export npm_config_ignore_scripts=true
    '';

    nativeBuildInputs = [
      makeWrapper
      bun
      coreutils
      pkg-config
      cargo
      rustc
    ];

    postPatch = ''
      cp ${./package.json} package.json
      cp ${./package-lock.json} package-lock.json
      cp ${./awrit-native-rs.package.json} awrit-native-rs/package.json
    '';

    postNpmInstall = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      rootDir="$PWD"
      pushd awrit-native-rs >/dev/null
        napiBin="$rootDir/node_modules/.bin/napi"
        "$napiBin" build --platform --release
        node scripts/fix-types.js
        rm -rf target
      popd >/dev/null
    '';

    installPhase = ''
          runHook preInstall

          mkdir -p $out/share/${storeRootName}
          cp -R . $out/share/${storeRootName}
          rm -rf \
            $out/share/${storeRootName}/.git \
            $out/share/${storeRootName}/.github \
            $out/share/${storeRootName}/docs \
            $out/share/${storeRootName}/awrit-native-rs/target
          rm -rf $out/share/${storeRootName}/node_modules/.cache || true
          rm -rf $out/share/${storeRootName}/node_modules/electron
          mkdir -p $out/share/${storeRootName}/node_modules/electron
          cat <<'ELECTRON_STUB' > $out/share/${storeRootName}/node_modules/electron/index.js
      const path = "@electronBin@";
      module.exports = path;
      module.exports.path = path;
      module.exports.default = path;
      ELECTRON_STUB
          cat <<'ELECTRON_PKG' > $out/share/${storeRootName}/node_modules/electron/package.json
      {
        "name": "electron",
        "version": "@electronVersion@",
        "main": "index.js"
      }
      ELECTRON_PKG
          substituteInPlace $out/share/${storeRootName}/node_modules/electron/package.json \
            --subst-var-by electronVersion "${version}"
          substituteInPlace $out/share/${storeRootName}/node_modules/electron/index.js \
            --subst-var-by electronBin "${electron}/bin/electron"
          echo ${version} > $out/share/${storeRootName}/.version

          mkdir -p $out/bin
          cat <<'SCRIPT' > $out/bin/awrit
      #!/usr/bin/env bash
      set -euo pipefail

      version="${version}"
      store_root="@storeRoot@"
      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
      state_root="$state_home/awrit"
      work_dir="$state_root/app"
      config_dir="$config_home/awrit"

      prepare_tree() {
        rm -rf "$work_dir"
        mkdir -p "$state_root"
        cp -a --no-preserve=mode,ownership "$store_root" "$work_dir"
        chmod -R u+w "$work_dir"
      }

      if [ ! -d "$work_dir" ] || [ ! -f "$work_dir/.version" ] || [ "$(<"$work_dir/.version")" != "$version" ]; then
        prepare_tree
      fi
      printf '%s' "$version" > "$work_dir/.version"

      mkdir -p "$config_dir"
      if [ ! -f "$config_dir/config.js" ]; then
        cp "$work_dir/config.js" "$config_dir/config.js"
      fi
      ln -sf "$config_dir/config.js" "$work_dir/config.js"

      export AWRIT_CONFIG_PATH="$config_dir/config.js"
      export TMPDIR="$state_root/tmp"
      export npm_config_cache="$state_root/npm-cache"
      export BUN_INSTALL_CACHE_DIR="$state_root/bun-cache"
      mkdir -p "$TMPDIR" "$npm_config_cache" "$BUN_INSTALL_CACHE_DIR"

      exec @bun@/bin/bun run "$work_dir/src/runner" "$@"
      SCRIPT
          chmod +x $out/bin/awrit

          substituteInPlace $out/bin/awrit \
            --subst-var-by storeRoot "$out/share/${storeRootName}" \
            --subst-var-by bun ${bun}

          wrapProgram $out/bin/awrit \
            --prefix PATH : ${lib.makeBinPath [coreutils git]}

          runHook postInstall
    '';

    meta = with lib; {
      description = "Web rendering in Kitty terminal";
      homepage = "https://github.com/chase/awrit";
      license = licenses.bsd3;
      maintainers = [];
      platforms = platforms.linux;
      mainProgram = "awrit";
    };
  }
