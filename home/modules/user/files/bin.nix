{config, ...}: let
  filesRoot = "${config.neg.hmConfigRoot}/files";
in {
  home.file."bin" = {
    source = filesRoot + "/bin";
    recursive = true;
  };
}
