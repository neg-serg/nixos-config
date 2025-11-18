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
  # CLI mail clients now come from modules/user/mail.nix (system-wide).
}
