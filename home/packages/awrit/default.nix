{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  bun,
  coreutils,
  pkg-config,
  python3,
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
      python3
      cargo
      rustc
    ];

    postPatch = ''
          cp ${./package.json} package.json
          cp ${./package-lock.json} package-lock.json
          if [ -f src/index.ts ]; then
            substituteInPlace src/index.ts \
              --replace-quiet "const CONFIG_PATH = '../config.js';" "const CONFIG_PATH = process.env.AWRIT_CONFIG_PATH ?? '../config.js';"
          fi
          if [ -f src/runner/index.ts ] && command -v python3 >/dev/null 2>&1; then
            substituteInPlace src/runner/index.ts \
              --replace-quiet "const CONFIG_PATH = '../config.js';" "const CONFIG_PATH = process.env.AWRIT_CONFIG_PATH ?? '../config.js';"
            python3 <<'PY'
      from pathlib import Path
      import base64

      path = Path("src/runner/index.ts")
      text = path.read_text()
      old = base64.b64decode(
          "aWYgKG9wdGlvbnMudmVyc2lvbikgewogIGNvbnN0IHZlcnNpb24gPSAoYXdhaXQgJGBnaXQgcmV2LXBhcnNlIC0tc2hvcnQgSEVBRGAucXVpZXQoKSkudGV4dCgpLnRyaW0oKTsKICBpZiAoc3Rkb3V0LmlzVFRZKSB7CiAgICBzdGRvdXQud3JpdGUoYCR7Qk9MRF9HUkVFTn1hd3JpdCR7UkVTRVR9ICR7dmVyc2lvbn1cbltgKTsKICB9IGVsc2UgewogICAgc3Rkb3V0LndyaXRlKHZlcnNpb24pOwogIH0KICBwcm9jZXNzLmV4aXQoMCk7Cn0KCg=="
      ).decode()
      new = base64.b64decode(
          "aWYgKG9wdGlvbnMudmVyc2lvbikgewogIGxldCB2ZXJzaW9uID0gJyc7CiAgdHJ5IHsKICAgIHZlcnNpb24gPSAoYXdhaXQgJGBnaXQgcmV2LXBhcnNlIC0tc2hvcnQgSEVBRGAucXVpZXQoKSkudGV4dCgpLnRyaW0oKTsKICB9IGNhdGNoIHsKICAgIHRyeSB7CiAgICAgIGNvbnN0IHBrZyA9IGF3YWl0IEJ1bi5maWxlKG5ldyBVUkwoJy4uL3BhY2thZ2UuanNvbicsIGltcG9ydC5tZXRhLnVybCkpLmpzb24oKTsKICAgICAgdmVyc2lvbiA9IChwa2c/LnZlcnNpb24gYXMgc3RyaW5nIHwgdW5kZWZpbmVkKSA/PyAndW5rbm93bic7CiAgICB9IGNhdGNoIHsKICAgICAgdmVyc2lvbiA9ICd1bmtub3duJzsKICAgIH0KICB9CiAgY29uc3QgbWVzc2FnZSA9IEJPTERfR1JFRU4gKyAnYXdyaXQnICsgUkVTRVQgKyAnICcgKyB2ZXJzaW9uOwogIGlmIChzdGRvdXQuaXNUVFkpIHsKICAgIHN0ZG91dC53cml0ZShtZXNzYWdlICsgIlxuIik7CiAgfSBlbHNlIHsKICAgIHN0ZG91dC53cml0ZSh2ZXJzaW9uKTsKICB9CiAgcHJvY2Vzcy5leGl0KDApOwp9Cgo="
      ).decode()

      if old not in text:
          raise SystemExit(0)
      path.write_text(text.replace(old, new, 1))
      PY
          fi
          cp ${./awrit-native-rs.package.json} awrit-native-rs/package.json
    '';

    postNpmInstall = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      pushd awrit-native-rs >/dev/null
        ../node_modules/.bin/napi build --platform --release
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
