{
  lib,
  python3,
  fetchFromGitHub,
  fetchurl,
}: let
  geoip2fast = python3.pkgs.buildPythonPackage rec {
    pname = "geoip2fast";
    version = "1.2.2";
    pyproject = true;

    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/source/g/geoip2fast/geoip2fast-${version}.tar.gz";
      hash = "sha256-OIFXAM7f6xl9UbS4czsNT3lls23hUUfBJVJxJPi0XWs=";
    };

    build-system = [python3.pkgs.setuptools];

    pythonImportsCheck = ["geoip2fast"];

    meta = with lib; {
      description = "Fast GeoIP2 lookup library with bundled data";
      homepage = "https://github.com/rabuchaim/geoip2fast";
      license = licenses.mit;
      maintainers = with maintainers; [];
      platforms = platforms.unix;
    };
  };
in
  python3.pkgs.buildPythonApplication rec {
    pname = "tewi";
    version = "2.0.0";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "anlar";
      repo = "tewi";
      rev = "3541f3d546c377ff53f9ef205f7251e1480a31ba";
      hash = "sha256-5QVF/4tdZmCVEw9X9A3hokfjBED1iJ8Pj0w68f+Lu4k=";
    };

    postPatch = ''
      cat >> src/tewi/app.tcss <<'EOF'
      $primary: #367bbf;
      $secondary: #0d1824;
      $background: #000000;
      $surface: #020202;
      $success: #3CAF88;
      $warning: #FFC44E;
      $error: #CF4F88;
      $accent: #98d3cb;
      $text: #6C7E96;
      $text-muted: #3D3D3D;
      EOF
    '';

    build-system = [python3.pkgs.setuptools];

    nativeBuildInputs = [python3.pkgs.pythonRelaxDepsHook];

    dependencies = with python3.pkgs; [
      textual
      transmission-rpc
      geoip2fast
      pyperclip
      qbittorrent-api
    ];

    pythonImportsCheck = ["tewi"];

    doCheck = false;

    meta = with lib; {
      description = "Text-based interface for Transmission, qBittorrent and Deluge";
      homepage = "https://github.com/anlar/tewi";
      license = licenses.gpl3Plus;
      maintainers = with maintainers; [];
      platforms = platforms.unix;
      mainProgram = "tewi";
    };
  }
