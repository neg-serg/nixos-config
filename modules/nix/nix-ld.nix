{pkgs, ...}: {
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc # glibc and libstdc++ runtime for foreign binaries
    ];
  };
}
