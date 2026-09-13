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
      installPhase =
        builtins.replaceStrings
          [
            "@QSBIN@"
            "@QTBASE@"
            "@QTPLUGINPREFIX@"
            "@QT5COMPAT@"
            "@QTPLUGINPREFIX_V2@"
            "@QTWAYLAND@"
            "@QTPLUGINPREFIX_V3@"
            "@QTSVG@"
            "@QTPLUGINPREFIX_V4@"
            "@QT5COMPAT_V2@"
            "@QTQMLPREFIX@"
            "@QTDECLARATIVE@"
            "@QTQMLPREFIX_V2@"
            "@QTPOSITIONING@"
            "@QTQMLPREFIX_V3@"
            "@QTSVG_V2@"
            "@QTQMLPREFIX_V4@"
            "@HIGHLIGHTING@"
            "@QTQMLPREFIX_V5@"
            "@QTMULTIMEDIA@"
            "@QTPLUGINPREFIX_V5@"
            "@QTMULTIMEDIA_V2@"
            "@QTQMLPREFIX_V6@"
            "@QSQMLPATH@"
            "@THEME@"
            "@QSPATH@"
            "@RUNTIMESHELL@"
          ]
          [
            "${qsBin}"
            "${pkgs.qt6.qtbase}"
            "${pkgs.qt6.qtbase.qtPluginPrefix}"
            "${pkgs.qt6.qt5compat}"
            "${pkgs.qt6.qtbase.qtPluginPrefix}"
            "${pkgs.kdePackages.qtwayland}"
            "${pkgs.qt6.qtbase.qtPluginPrefix}"
            "${pkgs.qt6.qtsvg}"
            "${pkgs.qt6.qtbase.qtPluginPrefix}"
            "${pkgs.qt6.qt5compat}"
            "${pkgs.qt6.qtbase.qtQmlPrefix}"
            "${pkgs.qt6.qtdeclarative}"
            "${pkgs.qt6.qtbase.qtQmlPrefix}"
            "${pkgs.qt6.qtpositioning}"
            "${pkgs.qt6.qtbase.qtQmlPrefix}"
            "${pkgs.qt6.qtsvg}"
            "${pkgs.qt6.qtbase.qtQmlPrefix}"
            "${pkgs.kdePackages.syntax-highlighting}"
            "${pkgs.qt6.qtbase.qtQmlPrefix}"
            "${pkgs.qt6.qtmultimedia}"
            "${pkgs.qt6.qtbase.qtPluginPrefix}"
            "${pkgs.qt6.qtmultimedia}"
            "${pkgs.qt6.qtbase.qtQmlPrefix}"
            "${qsQmlPath}"
            "${pkgs.hicolor-icon-theme}"
            "${qsPath}"
            "${pkgs.runtimeShell}"
          ]
          (builtins.readFile ./quickshell-wrapper-install.sh);
      meta.mainProgram = "qs";
    };
in
mkWrapper
