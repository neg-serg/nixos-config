{
  lib,
  stdenv,
  fetchFromGitHub,
  go,
}:

stdenv.mkDerivation rec {
  pname = "brrtfetch";
  version = "0-unstable-2026-01-10";

  src = fetchFromGitHub {
    owner = "ferrebarrat";
    repo = "brrtfetch";
    rev = "d32d15331089e31591520013fe121d44f29ca31d";
    hash = "sha256-4Z0eAyFCxrZl7wSAfSt02zktFd47bk7mV4k/OKjilpw=";
  };

  nativeBuildInputs = [ go ];

  buildPhase = ''
    export GOCACHE=$TMPDIR/go-cache
    go build -o brrtfetch ./go/main.go
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp brrtfetch $out/bin/
  '';

  meta = with lib; {
    description = "Render animated ASCII art from a GIF for your sysinfo fetcher of choice";
    homepage = "https://github.com/ferrebarrat/brrtfetch";
    license = licenses.mit;
    mainProgram = "brrtfetch";
    maintainers = [ ];
    platforms = platforms.all;
  };
}
