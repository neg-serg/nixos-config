{
  lib,
  stdenv,
  fetchFromGitHub,
  taglib,
}:
stdenv.mkDerivation {
  pname = "albumdetails";
  version = "0.1";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "albumdetails";
    rev = "91f4a546ccb42d82ae3b97462da73c284f05dbbe";
    hash = "sha256-9iaSyNqc/hXKc4iiDB6C7+2CMvKLWCRycsv6qVBD4wk=";
  };

  buildInputs = [ taglib ];

  # Provide TagLib headers/libs to Makefile's LDLIBS
  preBuild = ''
    makeFlagsArray+=(LDLIBS="-I${taglib}/include/taglib -L${taglib}/lib -ltag_c")
  '';

  # Upstream Makefile supports PREFIX+DESTDIR, but copying is simpler here
  installPhase = ''
    mkdir -p "$out/bin"
    install -m755 albumdetails "$out/bin/albumdetails"
  '';

  meta = with lib; {
    description = "Generate details for music album";
    homepage = "https://github.com/neg-serg/albumdetails";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "albumdetails";
  };
}
