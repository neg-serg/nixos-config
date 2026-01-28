{
  lib,
  python3Packages,
  fetchFromGitHub,
  pipewire,
  qt6,
}:

python3Packages.buildPythonApplication rec {
  pname = "cable";
  version = "0.9.27-unstable-2025-01-28";

  src = fetchFromGitHub {
    owner = "magillos";
    repo = "Cable";
    rev = "main";
    sha256 = "1kij4hhscclxhnbgy0aqpnfzh3l8a58378y8rgn0rd7hfkkvsgs9";
  };

  nativeBuildInputs = [
    qt6.wrapQtAppsHook
    python3Packages.setuptools
  ];

  buildInputs = [
    qt6.qtbase
  ];

  pyproject = true;

  propagatedBuildInputs = with python3Packages; [
    pyqt6
    dbus-python
    packaging
    requests
  ];

  # Needs pipewire tools in PATH
  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ pipewire ]}"
  ];

  # No tests in repo
  doCheck = false;

  meta = with lib; {
    description = "PipeWire Settings Manager";
    homepage = "https://github.com/magillos/Cable";
    license = licenses.gpl3Only;
    mainProgram = "cable";
    platforms = platforms.linux;
  };
}
