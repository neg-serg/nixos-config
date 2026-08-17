{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.efibootmgr # EFI boot manager
    pkgs.efivar # manipulate EFI variables
  ];
}
