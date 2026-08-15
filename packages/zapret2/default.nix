# zapret2 — DPI bypass via nfqueue (nfqws2)
# Upstream: https://github.com/bol-van/zapret
{
  lib,
  stdenv,
  fetchFromGitHub,
  libnetfilter_queue,
  libnfnetlink,
  libmnl,
  zlib,
  luajit,
  libcap,
}:

stdenv.mkDerivation rec {
  pname = "zapret2";
  version = "unstable-2026-08-03";

  src = fetchFromGitHub {
    owner = "bol-van";
    repo = "zapret";
    # Pinned (was floating master); hash verified to match this rev
    rev = "87e058624c72863db53bdaf7fb6f16576dddb6ab";
    hash = "sha256-fwwfEEH0fE4mRapN2Q3Xc7QGAmBM1un1P0tdDzmJnRk=";
  };

  buildInputs = [
    libnetfilter_queue
    libnfnetlink
    libmnl
    zlib
    luajit
    libcap
  ];

  # Root Makefile: `make all` builds binaries into binaries/my
  buildPhase = ''
    make all
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/zapret2
    # Binaries land in binaries/my (root Makefile); copy individual ones only
    for b in nfqws nfqws2 ip2net mdig; do
      find . -type f -name "$b" -executable -exec cp {} $out/bin/ \; 2>/dev/null || true
    done
    # Drop non-ELF artifacts that slipped in (e.g. OpenWrt shell wrappers)
    for f in $out/bin/*; do
      file "$f" | grep -q ELF || rm -f "$f"
    done
    chmod +x $out/bin/* 2>/dev/null || true
    cp -r common $out/share/zapret2/
    cp -r ipset $out/share/zapret2/
    cp blockcheck.sh config.default install_bin.sh $out/share/zapret2/ 2>/dev/null || true
    # Lua strategies + desync config (no build dirs with dangling symlinks)
    cp -r nfq/lua $out/share/zapret2/ 2>/dev/null || cp -r lua $out/share/zapret2/ 2>/dev/null || true
    cp -r nfq/*.conf $out/share/zapret2/ 2>/dev/null || true
  '';

  meta = with lib; {
    description = "DPI bypass tool — nfqueue-based traffic filter (nfqws2)";
    homepage = "https://github.com/bol-van/zapret";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
