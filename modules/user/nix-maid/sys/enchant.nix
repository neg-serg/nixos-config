{
  config,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkMerge [
    (n.mkHomeFiles {
      ".config/enchant/enchant.ordering".text = ''
        default:nuspell,hunspell
        en_US:nuspell,hunspell
        ru_RU:nuspell,hunspell
      '';
    })
    {
      environment.variables.ENCHANT_CONFIG_DIR = "${config.users.users.neg.home}/.config/enchant";
    }
  ];
}
