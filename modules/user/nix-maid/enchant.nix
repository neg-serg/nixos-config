{
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
in {
  config = n.mkHomeFiles {
    ".config/enchant/enchant.ordering".text = ''
      default:nuspell,hunspell
      en_US:nuspell,hunspell
      ru_RU:nuspell,hunspell
    '';
  };
}
