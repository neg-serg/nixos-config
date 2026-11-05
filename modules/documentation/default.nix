_: {
  documentation = {
    doc.enable = false;
    dev.enable = false;
    info.enable = false;
    # Package man pages are gated here: `documentation.man.enable` is what adds
    # "man" to environment.extraOutputsToInstall, and those -man outputs were
    # 25 MiB of the system closure. The `man` command itself stays (it comes
    # from the default packages); only pages shipped by Nix packages go away.
    man.enable = false;
    nixos.enable = false;
  };
}
