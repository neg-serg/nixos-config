{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.telegram-desktop # Telegram Desktop messenger
    pkgs.tdl # Telegram CLI uploader/downloader
  ];
}
