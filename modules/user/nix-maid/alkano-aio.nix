{
  stdenvNoCC,
  fetchFromGitHub,
  lib,
}:
stdenvNoCC.mkDerivation rec {
  pname = "Alkano-aio";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "Alkano-aio";
    rev = "v${version}";
    sha256 = "sha256-N+pM7TBtpQxk4Y/2TG2q7U8L3w44UkaAn1d9/kDeN8g=";
  };

  installPhase = ''
    mkdir -p $out/share/icons
    cp -r Alkano-aio/ $out/share/icons
  '';

  meta = with lib; {
    description = "Mirror of Alkano-aio";
    homepage = "https://github.com/neg-serg/Alkano-aio";
    license = licenses.gpl3;
    platforms = platforms.all;
    maintainers = with maintainers; [neg-serg];
  };
}
