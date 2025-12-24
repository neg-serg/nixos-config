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
  yandexPkg =
    if yandexInput != null
    then yandexInput.yandex-browser-stable
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
