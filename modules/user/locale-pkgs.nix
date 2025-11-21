{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.hunspell # classic spellchecker used across desktop apps
    pkgs.hunspellDicts.en_US # English dictionary for hunspell
    pkgs.hunspellDicts.ru_RU # Russian dictionary for hunspell
    pkgs.hyphen # hyphenation patterns for office suites
    pkgs.nuspell # modern spellchecker replacing aspell/hunspell
  ];
}
