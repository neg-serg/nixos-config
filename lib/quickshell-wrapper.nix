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
        makeWrapper ${qsBin} "$out/bin/qs" \
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
          --prefix XDG_DATA_DIRS : "${pkgs.adwaita-icon-theme}/share" \
          --prefix XDG_DATA_DIRS : "${pkgs.hicolor-icon-theme}/share" \ # Default fallback theme used by implementations of the ico...
          --set QT_QPA_PLATFORM wayland \
          --set QML_XHR_ALLOW_FILE_READ 1 \
          --prefix PATH : ${qsPath}
        ln -s "$out/bin/qs" "$out/bin/quickshell"
      '';
      meta.mainProgram = "qs";
    };
in
mkWrapper
