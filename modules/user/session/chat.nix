{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.tdl # Telegram CLI uploader/downloader
  ];
}
