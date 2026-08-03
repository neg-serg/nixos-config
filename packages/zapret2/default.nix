# zapret2 — DPI bypass via nfqueue (nfqws2)
# Upstream: https://github.com/bol-van/zapret
{ lib, stdenv, fetchFromGitHub, libnetfilter_queue, libnfnetlink, libmnl, zlib, luajit }:

stdenv.mkDerivation rec {
  pname = "zapret2";
  version = "unstable-2026-07-08";

  src = fetchFromGitHub {
    owner = "bol-van";
    repo = "zapret";
    rev = "master";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # fill after first build
  };

  nativeBuildInputs = [];
  buildInputs = [ libnetfilter_queue libnfnetlink libmnl zlib luajit ];

  buildPhase = ''
    make -C nfq2
    make -C ip2net
    make -C mdig
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp nfq2/nfqws2 $out/bin/
    cp ip2net/ip2net $out/bin/
    cp mdig/mdig $out/bin/
    mkdir -p $out/share/zapret2
    cp -r lua $out/share/zapret2/
    cp -r common $out/share/zapret2/
    cp -r ipset $out/share/zapret2/
    cp blockcheck2.sh $out/share/zapret2/
  '';

  meta = with lib; {
    description = "DPI bypass tool — nfqueue-based traffic filter (nfqws2)";
    homepage = "https://github.com/bol-van/zapret";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
