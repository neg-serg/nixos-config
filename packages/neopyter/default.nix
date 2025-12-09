{
  lib,
  buildPythonPackage,
  fetchPypi,
  hatchling,
  aiohttp,
  jupyter-server,
  pygount,
  python-multipart,
}:
buildPythonPackage rec {
  pname = "neopyter";
  version = "0.3.2";
  format = "pyproject";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-w5gOSKdRc163UPFmrf/SGtkKRU5C2KOGb6aR6RT0FiM=";
  };

  nativeBuildInputs = [hatchling];

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
    maintainers = [];
  };
}
