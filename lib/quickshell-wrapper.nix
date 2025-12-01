{
  lib,
  pkgs,
}: let
  mkWrapper = {
    qsPkg,
    extraPath ? [],
  }: let
    qsBin = lib.getExe' qsPkg "qs";
    qsQmlPath = "${qsPkg}/${pkgs.qt6.qtbase.qtQmlPrefix}";
    qsPath =
      pkgs.lib.makeBinPath
      (
        [pkgs.fd pkgs.coreutils]
        ++ extraPath
      );
  in
    pkgs.stdenv.mkDerivation {
      name = "quickshell-wrapped";
      buildInputs = [pkgs.makeWrapper];
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
          --set QT_QPA_PLATFORM wayland \
          --set QML_XHR_ALLOW_FILE_READ 1 \
          --prefix PATH : ${qsPath}
      '';
    };
in
  mkWrapper
