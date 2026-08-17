{
  lib,
  fetchFromGitHub,
  python3,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "pycamilladsp-plot";
  version = "4.1.0";

  src = fetchFromGitHub {
    owner = "HEnquist";
    repo = "pycamilladsp-plot";
    rev = "v${version}";
    hash = "sha256-voz/WXG/pSDHEDplHex37WcxDFMryfQVXVbeUichUxo=";
  };

  pyproject = true;
  build-system = [ python3.pkgs.setuptools ];

  dependencies = [
    python3.pkgs.jsonschema
    python3.pkgs.pyyaml
  ];

  meta = with lib; {
    description = "Validate, evaluate and plot configs and filters for CamillaDSP";
    homepage = "https://github.com/HEnquist/pycamilladsp-plot";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
