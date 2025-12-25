{
  lib,
  python3Packages,
  laion_clap,
}:
python3Packages.buildPythonApplication {
  pname = "music-clap";
  version = "0.1.0";
  format = "pyproject";
  src = ./.;

  build-system = [python3Packages.setuptools];
  propagatedBuildInputs = [laion_clap];

  doCheck = false;
  meta = {
    description = "CLI wrapper around LAION-CLAP to produce audio embeddings";
    homepage = "https://github.com/LAION-AI/CLAP";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [];
  };
}
