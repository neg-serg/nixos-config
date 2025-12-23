{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.nchat # terminal-first Telegram client
    pkgs.tdl # Telegram CLI uploader/downloader
    pkgs.telegram-desktop # Telegram GUI client
    pkgs.vesktop # Discord (Vencord) desktop client
  ];
}
