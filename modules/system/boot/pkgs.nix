{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.efibootmgr # rule EFI boot
    pkgs.efivar # manipulate EFI variables
    pkgs.os-prober # detect other OSes on drives
    pkgs.sbctl # debugging and troubleshooting Secure Boot
  ];
}
