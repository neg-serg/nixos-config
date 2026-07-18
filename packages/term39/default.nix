##
# Package: term39
# Purpose: Retro-styled terminal multiplexer with MS-DOS aesthetic
# Source: https://github.com/alejandroqh/term39 (v1.5.2)
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
let
  version = "1.5.2";

  src = fetchFromGitHub {
    owner = "alejandroqh";
    repo = "term39";
    rev = "v${version}";
    hash = lib.fakeHash; # Set after first build: nix build 2>&1 | grep "got:"
  };
in
rustPlatform.buildRustPackage {
  pname = "term39";
  inherit version src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  # Full feature set: clipboard, framebuffer-backend, battery, PAM lockscreen
  buildFeatures = [ "full" ];

  meta = with lib; {
    description = "Modern retro-styled terminal multiplexer with MS-DOS aesthetic";
    longDescription = ''
      Full-screen terminal multiplexer with authentic DOS-style rendering,
      supporting both Unicode and ASCII rendering modes. Includes optional framebuffer
      backend for direct Linux console rendering, PAM lockscreen, and battery monitoring.
    '';
    homepage = "https://github.com/alejandroqh/term39";
    license = licenses.mit;
    mainProgram = "term39";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
