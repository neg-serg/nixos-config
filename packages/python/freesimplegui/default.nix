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
  version = "5.1.1";
  format = "pyproject";

  src = fetchPypi {
    pname = "freesimplegui";
    inherit version;
    sha256 = "sha256-LwlGx6wiHJl5KRgcvnUm40L/9fwpGibR1yYoel3ZZPs=";
  };

  # I will update the hash in the next step once I have the prefetched output.

  nativeBuildInputs = [setuptools wheel];
  propagatedBuildInputs = [tkinter];

  doCheck = false;

  meta = with lib; {
    description = "Open source Python GUI framework. Replaces PySimpleGUI";
    homepage = "https://github.com/spyoungtech/FreeSimpleGUI";
    license = licenses.lgpl3Only;
  };
}
