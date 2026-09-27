_: {
  # 32-bit rdma-core comes in through services.pipewire.alsa.support32Bit
  # (pkgsi686Linux.pipewire → spandsp → libpcap → rdma-core) and builds
  # its man pages with pandoc. For i686 that drags in all of 32-bit Haskell:
  # pandoc-cli-i686, two GHCs (9.6.7 + 9.10.3) and ~430 packages — hours of build
  # time for man pages the 32-bit branch does not need.
  # We disable the man pages only for 32-bit rdma-core: the upstream option
  # -DNO_MAN_PAGES=1 (CMakeLists.txt:538) + pandoc from nativeBuildInputs.
  # The "man" output stays declared in the derivation, so we create the empty
  # $man directory ourselves — otherwise Nix fails with "failed to produce output path 'man'".
  nixpkgs.overlays = [
    (_: prev: {
      pkgsi686Linux = prev.pkgsi686Linux.extend (
        _: p32: {
          rdma-core = p32.rdma-core.overrideAttrs (old: {
            cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DNO_MAN_PAGES=1" ];
            nativeBuildInputs = builtins.filter (x: (x.pname or "") != "pandoc-cli") (
              old.nativeBuildInputs or [ ]
            );
            postInstall = (old.postInstall or "") + ''
              mkdir -p $man
            '';
          });
        }
      );
    })
  ];
}
