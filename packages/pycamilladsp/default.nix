{
  lib,
  fetchFromGitHub,
  python3,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "pycamilladsp";
  version = "4.0.0";

  src = fetchFromGitHub {
    owner = "HEnquist";
    repo = "pycamilladsp";
    rev = "v${version}";
    hash = "sha256-2qAj/vKwAA7tCqvHWazPeBbvd4smEtG5urdIVkRFThk=";
  };

  pyproject = true;
  build-system = [ python3.pkgs.setuptools ];

  dependencies = [
    python3.pkgs.pyyaml
    python3.pkgs.websocket-client
  ];

  meta = with lib; {
    description = "Python library for communicating with CamillaDSP";
    homepage = "https://github.com/HEnquist/pycamilladsp";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
