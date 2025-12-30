{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  webEnabled = (config.features.web.enable or false) || (config.features.web.yandex.enable or false);
in {
  imports = [inputs.yandex-browser.nixosModules.system];

  config = lib.mkIf webEnabled {
    programs.yandex-browser = {
      enable = true;
      package = "beta";
      # extensionInstallBlocklist = [ "imjepfoebignfgmogbbghpbkbcimgfpd" ]; # "buggy" extension in beta
    };

    environment.systemPackages = lib.mkAfter [
      pkgs.passff-host # native messaging host for PassFF Firefox extension
    ];
  };
}
