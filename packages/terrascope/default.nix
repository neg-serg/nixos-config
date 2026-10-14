##
# Package: terrascope
# Purpose: Interactive world map for the terminal (curses + Unicode Braille)
#   with live layers — aircraft (OpenSky), city weather (Open-Meteo), radar
#   (RainViewer/LibreWXR), earthquakes (USGS) and day/night bands.
# Notes:
#   - Pure-python app built from the PyPI sdist; upstream hatches the wheel
#     from src/terrascope, so the bundled assets/ (default config, country,
#     airport and place reference data) travel with the package.
#   - The sdist carries no test suite, so checks are off and
#     pythonImportsCheck proves the module imports with its runtime deps.
#   - Large Natural Earth map data is not bundled: it is downloaded into
#     $XDG_CACHE_HOME/terrascope on the first run and reused afterwards.
{
  lib,
  python3,
  fetchPypi,
}:
let
  pypi = python3.pkgs;
in
pypi.buildPythonApplication rec {
  pname = "terrascope";
  version = "0.2.3";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-9mQslM9XuIZaHEVusbM3jWs9Gg1h/6YXUP1ZyAxwCxs=";
  };

  build-system = [ pypi.hatchling ];

  dependencies = [
    pypi.numpy
    pypi.pillow
    pypi.pyshp
    pypi.pyyaml
  ];

  doCheck = false;
  pythonImportsCheck = [ "terrascope" ];

  meta = lib.mkMeta {
    description = "Interactive world map for the terminal (braille) with live aircraft, weather and earthquake layers";
    homepage = "https://github.com/a-shygun/terrascope";
    license = lib.licenses.mit;
    mainProgram = "terrascope";
  };
}
