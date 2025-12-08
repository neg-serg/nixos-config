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
    sha256 = "1qd13rqsjy7hqkg5gz0371m53q52z5nphwqb1k0cqy0pmycprryk";
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
