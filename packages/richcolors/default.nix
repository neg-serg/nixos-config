{
  lib,
  python3,
  fetchFromGitHub,
}:
python3.pkgs.buildPythonApplication rec {
  pname = "richcolors";
  version = "unstable-2024-10-07";
  format = "other";

  src = fetchFromGitHub {
    owner = "Rizen54";
    repo = "richcolors";
    rev = "777eec6fe954f672ff5715304e0bc5315113664b";
    hash = "sha256-lzqNDnMFVGgXlshq20Uca86ctRn1p6VFsAc0QCe7fnU=";
  };

  propagatedBuildInputs = with python3.pkgs; [
    pillow
  ];

  pythonImportsCheck = ["PIL"];

  installPhase = ''
    runHook preInstall

    install -Dm755 richcolors $out/bin/richcolors
    patchShebangs $out/bin/richcolors

    runHook postInstall
  '';

  doCheck = false;

  meta = with lib; {
    description = "CLI that renders color palette images from hex code files";
    homepage = "https://github.com/Rizen54/richcolors";
    license = licenses.unfree;
    maintainers = with maintainers; [];
    platforms = platforms.unix;
    mainProgram = "richcolors";
  };
}
