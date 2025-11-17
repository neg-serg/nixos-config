{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./accounts
    ./isync
    ./mutt
    ./khal # better calendar
    ./msmtp
    ./notmuch
    ./vdirsyncer
  ];
  home.packages = config.lib.neg.pkgsList (
    let
      groups = {
        core = [
          pkgs.himalaya # modern cli for mail
          pkgs.kyotocabinet # mail client helper library
          pkgs.neomutt # mail client
        ];
      };
      flags = {core = config.features.mail.enable or false;};
    in
      config.lib.neg.mkEnabledList flags groups
  );
}
