{
  lib,
  pkgs,
  config,
  qsProvider ? null,
  ...
}:
with lib; let
  qsPkg =
    if qsProvider != null
    then (qsProvider pkgs)
    else pkgs.emptyFile;
  qsPath = pkgs.lib.makeBinPath [
    pkgs.fd # fast file finder (used by scripts)
    pkgs.coreutils # basic UNIX tools for PATH
  ];
  qsBin = lib.getExe' qsPkg "qs";
  # Quickshell ships its own QML module; include its QML dir explicitly.
  qsQmlPath = "${qsPkg}/${pkgs.qt6.qtbase.qtQmlPrefix}";
  quickshellWrapped = pkgs.stdenv.mkDerivation {
    name = "quickshell-wrapped";
    buildInputs = [pkgs.makeWrapper]; # for makeWrapper helper
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      makeWrapper ${qsBin} $out/bin/qs \
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
  mkIf (config.features.gui.enable && (config.features.gui.qt.enable or false) && (config.features.gui.quickshell.enable or false) && (! (config.features.devSpeed.enable or false))) {
    home.packages = [quickshellWrapped]; # quickshell wrapper with required env paths
    # Expose the wrapped package for other modules (e.g., systemd service ExecStart)
    neg.quickshell.wrapperPackage = quickshellWrapped;
  }
