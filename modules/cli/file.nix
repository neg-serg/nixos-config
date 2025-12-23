{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.convmv # convert filename encodings
    pkgs.dos2unix # file conversion
    pkgs.fd # better find
    pkgs.file # detect file type by content
    pkgs.massren # massive rename utility
    pkgs.nnn # CLI file manager
    pkgs.ranger # curses file manager needed by termfilechooser
    pkgs.stow # manage farms of symlinks
    pkgs.zoxide # smarter cd with ranking
  ];
}
