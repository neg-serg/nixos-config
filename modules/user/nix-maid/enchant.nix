{...}: {
  # Always enable for neg user if this module is imported,
  # mirroring the previous behavior in envs/default.nix
  users.users.neg.maid.file.home = {
    ".config/enchant/enchant.ordering".text = ''
      default:nuspell,hunspell
      en_US:nuspell,hunspell
      ru_RU:nuspell,hunspell
    '';
  };
}
