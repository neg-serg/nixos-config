{
  lib,
  stdenv,
  fetchurl,
  autoreconfHook,
  pkg-config,
  makeWrapper,
  bash,
  perl,
  zstd,
  perlPackages,
  libHX,
  util-linux,
  pciutils,
  libxcb,
}:
stdenv.mkDerivation rec {
  pname = "hxtools";
  version = "20250309";

  src = fetchurl {
    url = "https://inai.de/files/${pname}/${pname}-${version}.tar.zst";
    hash = "sha256-2ItcEiMe0GzgJ3MxZ28wjmXGSbZtc7BHpkpKIAodAwA=";
  };

  nativeBuildInputs = [
    autoreconfHook # regenerate autotools scripts
    pkg-config # configure-time dependency discovery
    zstd # unpack upstream .tar.zst
    makeWrapper # wrap scripts with runtime envs
  ];

  buildInputs = [
    bash # shell for bundled scripts and wrappers
    perl # perl helpers installed by upstream
    perlPackages.TextCSV_XS # CSV parser used by man2html
    libHX # shared helper library for the tool suite
    util-linux # optional libs for block/filesystem helpers
    pciutils # optional PCI helpers
    libxcb # optional X11/xcb support
  ];

  configureFlags = [
    "--with-kbddatadir=/run/current-system/sw/share/kbd"
    "--with-x11fontdir=/run/current-system/sw/share/fonts"
  ];

  installFlags = [
    "kbddatadir=$out/share/kbd"
    "x11fontdir=$out/share/fonts"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    wrapProgram "$out/bin/man2html" \
      --prefix PERL5LIB : "${perlPackages.TextCSV_XS}/lib/perl5/site_perl"
  '';

  meta = with lib; {
    description = "Collection of small admin, git, and media utilities";
    homepage = "https://codeberg.org/jengelh/hxtools";
    license = with licenses; [
      mit
      bsd2Patent
      lgpl21Plus
      gpl2Plus
    ];
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };
}
