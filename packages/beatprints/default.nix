{
  lib,
  python3,
  fetchFromGitHub,
}: let
  pyletteFixed = python3.pkgs.pylette.overridePythonAttrs (_: {
    doCheck = false;
  });
in
  python3.pkgs.buildPythonApplication rec {
    pname = "beatprints";
    version = "1.1.5";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "TrueMyst";
      repo = "BeatPrints";
      rev = "v${version}";
      hash = "sha256-7h2MbU6wPqcRhWijdMyd7sTf3UVNCX+5JUNytKr5/EM=";
    };

    build-system = [python3.pkgs.poetry-core];
    nativeBuildInputs = [python3.pkgs.pythonRelaxDepsHook];
    pythonRelaxDeps = ["pillow" "rich"];

    dependencies =
      [pyletteFixed]
      ++ (with python3.pkgs; [
        fonttools
        lrclibapi
        pillow
        questionary
        requests
        rich
        spotipy
        toml
      ]);

    pythonImportsCheck = ["BeatPrints"];

    doCheck = false;

    meta = with lib; {
      description = "Generate Spotify posters with themed layouts and LRClib lyrics";
      homepage = "https://github.com/TrueMyst/BeatPrints";
      license = licenses.cc-by-nc-sa-40;
      mainProgram = "beatprints";
      platforms = platforms.unix;
    };
  }
