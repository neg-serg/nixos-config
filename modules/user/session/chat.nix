{
  pkgs,
  lib,
  config,
  ...
}:
{
  environment.systemPackages = [
    pkgs.nchat # terminal-first Telegram client
    pkgs.tdl # Telegram CLI uploader/downloader
    pkgs.telegram-desktop # Telegram GUI client
  ]
  ++ (lib.optionals (config.features.apps.discord.enable or false) [
    pkgs.vesktop # Discord (Vencord) desktop client
  ]);
}
