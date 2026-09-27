_: {
  # 32-битный rdma-core приезжает через services.pipewire.alsa.support32Bit
  # (pkgsi686Linux.pipewire → spandsp → libpcap → rdma-core) и собирает
  # man-страницы через pandoc. Для i686 это вытягивает весь 32-битный Haskell:
  # pandoc-cli-i686, два GHC (9.6.7 + 9.10.3) и ~430 пакетов — часы сборки
  # ради man-ов, которые 32-битной ветке не нужны.
  # Гасим man-страницы только у 32-битного rdma-core: апстримная опция
  # -DNO_MAN_PAGES=1 (CMakeLists.txt:538) + pandoc из nativeBuildInputs.
  # Вывод "man" в деривации остаётся объявленным, поэтому пустой каталог $man
  # создаём сами — иначе Nix падает на "failed to produce output path 'man'".
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
