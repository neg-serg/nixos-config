{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "inferno";
  version = "0.12.7";

  src = fetchFromGitHub {
    owner = "jonhoo";
    repo = "inferno";
    rev = "v${version}";
    hash = "sha256-NSeha9eDWOv1PmzwP6oVsZ0ueYm7G3La/xn2NP7z3n8=";
  };

  cargoHash = "sha256-vvUgosyPHcm6M7Z8PSNKXHEPjZObfDcTKjSJuK04mgU=";

  doCheck = false;

  meta = with lib; {
    description = "Rust port of the FlameGraph performance profiling tool suite";
    homepage = "https://github.com/jonhoo/inferno";
    license = licenses.cddl;
    maintainers = [ ];
    mainProgram = "inferno-flamegraph";
    platforms = platforms.linux;
  };
}
