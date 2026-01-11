{
  lib,
  buildPythonPackage,
  fetchPypi,
  aiohttp,
  jupyter-server,
  pygount,
  python-multipart,
}:
buildPythonPackage rec {
  pname = "neopyter";
  version = "0.3.2";
  format = "wheel";

  src = fetchPypi {
    inherit pname version;
    format = "wheel";
    dist = "py3";
    python = "py3";
    hash = "sha256-W4MZCQxqogBD5hONNlrcnrlT4DyUgiIjHhSiVJ+MNKs=";
  };

  propagatedBuildInputs = [
    aiohttp
    jupyter-server
    pygount
    python-multipart
  ];

  doCheck = false;

  meta = with lib; {
    description = "Neovim plugin for JupyterLab";
    homepage = "https://github.com/SUSTech-data/neopyter";
    license = licenses.mit;
    maintainers = [ ];
  };
}
