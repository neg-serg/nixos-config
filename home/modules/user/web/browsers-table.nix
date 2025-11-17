{
  lib,
  pkgs,
  yandexBrowser ? null,
  nyxt4 ? null,
  ...
}: let
  nyxtPkg =
    if nyxt4 != null
    then nyxt4
    else if lib.hasAttr "nyxt4-bin" pkgs
    then pkgs.nyxt4-bin
    else pkgs.nyxt;
  # Floorp upstream source package is deprecated in nixpkgs >= 12.x; always use floorp-bin.
  floorpPkg = pkgs.floorp-bin;
in
  {
    firefox = {
      name = "firefox";
      pkg = pkgs.firefox;
      bin = lib.getExe' pkgs.firefox "firefox";
      desktop = "firefox.desktop";
      newTabArg = "-new-tab";
    };
    librewolf = {
      name = "librewolf";
      pkg = pkgs.librewolf;
      bin = lib.getExe' pkgs.librewolf "librewolf";
      desktop = "librewolf.desktop";
      newTabArg = "-new-tab";
    };
    nyxt = {
      name = "nyxt";
      pkg = nyxtPkg;
      bin = lib.getExe' nyxtPkg "nyxt";
      desktop = "nyxt.desktop";
      newTabArg = "";
    };
    floorp = {
      name = "floorp";
      pkg = floorpPkg;
      bin = lib.getExe' floorpPkg "floorp";
      desktop = "floorp.desktop";
      newTabArg = "-new-tab";
    };
  }
  // (lib.optionalAttrs (yandexBrowser != null) {
    yandex = {
      name = "yandex";
      pkg = yandexBrowser.yandex-browser-stable;
      bin = lib.getExe' yandexBrowser.yandex-browser-stable "yandex-browser-stable";
      desktop = "yandex-browser.desktop";
      newTabArg = "--new-tab";
    };
  })
