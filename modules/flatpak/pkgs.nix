{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.flatpak # runtime manager for sandboxed desktop apps
    pkgs.flatpak-builder # build tool for custom Flatpak manifests
  ];
}
