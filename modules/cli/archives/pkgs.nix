{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.lbzip2 # parallel bzip2
    pkgs.p7zip # 7z x
    pkgs.pzip # parallel zip archiver
    pkgs.rapidgzip # fast gzip unarchiver
    pkgs.unar # archive extractor with broad format support
    pkgs.unrar-wrapper # unrar
    pkgs.unzip # zip archive operations
    pkgs.xz # xz archiver
    pkgs.zip # zip archiver
  ];
}
