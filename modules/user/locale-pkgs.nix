{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.enchant # glue/CLI to probe spellchecker providers (hunspell/nuspell backends)
    pkgs.hunspell # classic spellchecker used across desktop apps
    pkgs.hunspellDicts.en_US # English dictionary for hunspell
    pkgs.hunspellDicts.ru_RU # Russian dictionary for hunspell
    pkgs.hyphen # hyphenation patterns for office suites
    pkgs.nuspell # modern spellchecker replacing aspell/hunspell
  ];
}
