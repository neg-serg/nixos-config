{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.tdl # Telegram CLI uploader/downloader
    pkgs.telegram-desktop # Telegram GUI client
  ];
}
