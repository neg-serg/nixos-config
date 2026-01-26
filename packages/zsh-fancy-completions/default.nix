{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "zsh-fancy-completions";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "z-shell";
    repo = "zsh-fancy-completions";
    rev = "master";
    sha256 = "sha256-sFK+ettrfK1rBKyUbzL4fCaDtxFdPuvpLYZ1ORSQ3cY=";
  };

  installPhase = ''
    mkdir -p $out/share/zsh/plugins/zsh-fancy-completions
    cp -r * $out/share/zsh/plugins/zsh-fancy-completions
  '';

  meta = with lib; {
    description = "Advanced completions for Zsh";
    homepage = "https://github.com/z-shell/zsh-fancy-completions";
    license = licenses.gpl3;
    platforms = platforms.unix;
  };
}
