{
  lib,
  pkgs,
}:
let
  mkWrapper =
    {
      qsPkg,
      extraPath ? [ ],
    }:
    let
      qsBin = lib.getExe' qsPkg "qs";
      qsQmlPath = "${qsPkg}/${pkgs.qt6.qtbase.qtQmlPrefix}";
      qsPath = pkgs.lib.makeBinPath (
        [
          pkgs.fd # fast find replacement
          pkgs.coreutils # basic file/text utilities
        ]
        ++ extraPath
      );
    in
    pkgs.stdenv.mkDerivation {
      name = "quickshell-wrapped";
      buildInputs = [ pkgs.makeWrapper ]; # utility to create shell wrappers
      dontUnpack = true;
      installPhase = ''
                mkdir -p "$out/bin"
                makeWrapper ${qsBin} "$out/bin/.qs-wrapped" \
                  --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
                  --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qt5compat}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
                  --prefix QT_PLUGIN_PATH : "${pkgs.kdePackages.qtwayland}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
                  --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qt5compat}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtpositioning}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${pkgs.kdePackages.syntax-highlighting}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
                  --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
                  --prefix QML2_IMPORT_PATH : "${qsQmlPath}" \
                  --prefix XDG_DATA_DIRS : "${pkgs.hicolor-icon-theme}/share" \
                  --set QT_QPA_PLATFORM wayland \
                  --set QML_XHR_ALLOW_FILE_READ 1 \
                  --prefix PATH : ${qsPath}

                # A bare `qs` must never draw a second panel: quickshell only exits on an
                # explicit IPC kill (`qs kill`), so starting it while the panel already
                # runs leaves two instances, two overlapping bars and a D-Bus conflict.
                # Outside systemd, drop any leftover instance of this config and hand the
                # panel back to systemd so it stays supervised. Anything with arguments
                # (ipc / kill / -p ...) goes to the real binary untouched, and under
                # systemd (INVOCATION_ID set) nothing is intercepted, so the unit can
                # always start even if another instance is around.
                cat > "$out/bin/qs" <<'SHIM'
        #!@shell@
        if [ -z "$INVOCATION_ID" ] && [ "$#" -eq 0 ]; then
          for _ in 1 2 3 4 5; do
            @wrapped@ kill >/dev/null 2>&1 || break
            sleep 0.3
          done
          if command -v systemctl >/dev/null 2>&1 && systemctl --user start quickshell.service >/dev/null 2>&1; then
            exit 0
          fi
        fi
        exec @wrapped@ "$@"
        SHIM
                substituteInPlace "$out/bin/qs" \
                  --replace-fail '@shell@' ${pkgs.runtimeShell} \
                  --replace-fail '@wrapped@' "$out/bin/.qs-wrapped"
                chmod +x "$out/bin/qs"
                ln -s qs "$out/bin/quickshell"
      '';
      meta.mainProgram = "qs";
    };
in
mkWrapper
