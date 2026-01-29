{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.telegram-desktop
    pkgs.tdl # Telegram CLI uploader/downloader
  ];
}
