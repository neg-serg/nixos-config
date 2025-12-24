{
  lib,
  config,
  pkgs,
  inputs ? {},
  yandexBrowserProvider ? null,
  ...
}: let
  webEnabled = config.features.web.enable or false;
  yandexEnabled = webEnabled && (config.features.web.yandex.enable or false);
  yandexInput =
    if yandexBrowserProvider != null
    then yandexBrowserProvider pkgs
    else if inputs ? "yandex-browser"
    then inputs."yandex-browser".packages.${pkgs.stdenv.hostPlatform.system}
    else null;
  yandexPkgRaw =
    if yandexInput != null
    then yandexInput.yandex-browser-stable
    else null;
  yandexPkg =
    if yandexPkgRaw != null
    then
      yandexPkgRaw.overrideAttrs (_: {
        version = "25.10.1.1173-1";
        src = pkgs.fetchurl {
          url = "http://repo.yandex.ru/yandex-browser/deb/pool/main/y/yandex-browser-stable/yandex-browser-stable_25.10.1.1173-1_amd64.deb";
          hash = "sha256-31ec155f50ba0ec9c4d4841322ead9b196429926ededaee0c4c9b4caa937aa64";
        };
      })
    else null;
  packages =
    lib.optionals webEnabled [
      pkgs.google-chrome # Google Chrome browser
      pkgs.passff-host # native messaging host for PassFF Firefox extension
    ]
    ++ lib.optionals (yandexEnabled && yandexPkg != null) [yandexPkg]
    # Yandex Browser (Chromium-based with Russian services)
    ;
in {
  config = lib.mkMerge [
    (lib.mkIf yandexEnabled {
      assertions = [
        {
          assertion = yandexPkg != null;
          message = "features.web.yandex.enable = true but yandex-browser input was not provided.";
        }
      ];
    })
    (lib.mkIf webEnabled {
      environment.systemPackages = lib.mkAfter packages;
    })
  ];
}
