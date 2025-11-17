{config, ...}: {
  home.file."bin" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.neg.dotfilesRoot}/bin";
    recursive = false;
  };
}
