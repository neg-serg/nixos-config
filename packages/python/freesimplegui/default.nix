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
    pname = "FreeSimpleGUI";
    inherit version;
    sha256 = "12prapfg57adkwx9f28kdlsrhffc9zwi2s95a9qyiag9b1khx2p5";
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
