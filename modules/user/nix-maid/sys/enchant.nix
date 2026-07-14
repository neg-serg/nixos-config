{
  config,
  lib,
  neg,
  ...
}:
{
  config = lib.mkMerge [
    (neg.mkHomeFiles {
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
