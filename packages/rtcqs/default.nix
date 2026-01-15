{
  lib,
  python3Packages,
  fetchFromGitea,
}:
python3Packages.buildPythonApplication rec {
  pname = "rtcqs";
  version = "0.6.7";

  format = "pyproject";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "rtcqs";
    repo = "rtcqs";
    rev = "v${version}";
    sha256 = "1kc3niyaq4m8di68832pgfb1b0m54q5gm68dwlzwwilgxi61ifzc";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
  ];

  propagatedBuildInputs = with python3Packages; [

    tkinter
  ];

  pythonImportsCheck = [ "rtcqs" ];

  postInstall = ''
    install -Dm644 ${src}/rtcqs.desktop $out/share/applications/rtcqs.desktop
    install -Dm644 ${src}/rtcqs_logo.svg $out/share/icons/hicolor/scalable/apps/rtcqs.svg
  '';

  meta = with lib; {
    description = "Linux audio performance analyzer";
    homepage = "https://codeberg.org/rtcqs/rtcqs";
    license = licenses.mit;
    mainProgram = "rtcqs";
    platforms = platforms.linux;
  };
}
