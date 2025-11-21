{
  lib,
  config,
  ...
}:
with lib;
  mkIf config.features.mail.enable {
    # Enable the imapnotify service itself
    services.imapnotify.enable = true;

    # And just enable it for the gmail account, without redefining the whole account
    accounts.email.accounts."gmail".imapnotify.enable = true;
  }