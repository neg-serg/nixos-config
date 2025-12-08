{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  wheel,
  tkinter,
}:
buildPythonPackage rec {
  pname = "freesimplegui";
  version = "5.2.0.post1";

  format = "pyproject";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-5YoOZ1jpqehxUiVpEflPzDmYNW0TCZc6n02d8txV+Yo=";
  };

  nativeBuildInputs = [
    setuptools
    wheel
  ];

  propagatedBuildInputs = [tkinter];

  pythonImportsCheck = ["FreeSimpleGUI"];

  meta = with lib; {
    description = "Free, drop-in compatible fork of PySimpleGUI";
    homepage = "https://github.com/spyoungtech/FreeSimpleGui";
    license = licenses.lgpl3Plus;
    platforms = platforms.linux ++ platforms.darwin;
  };
}
