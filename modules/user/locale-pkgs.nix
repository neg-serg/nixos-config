{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.hunspell
    pkgs.hunspellDicts.en_US
    pkgs.hunspellDicts.ru_RU
    pkgs.hyphen
    pkgs.nuspell
  ];
}
