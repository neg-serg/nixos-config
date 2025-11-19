{
  lib,
  python3Packages,
  coreutils,
  ...
}:
python3Packages.buildPythonApplication rec {
  pname = "neg-pretty-printer";
  version = "0.1.0";

  format = "pyproject";
  src = ./.;

  nativeBuildInputs = with python3Packages; [setuptools wheel];
  propagatedBuildInputs = with python3Packages; [colored];

  # Ensure external tools used by CLI are available (wc from coreutils)
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [coreutils])
  ];

  meta = with lib; {
    description = "Custom pretty-printer utilities (colors + file info)";
    homepage = "https://github.com/neg-serg/nixos-home";
    license = licenses.unlicense;
    platforms = platforms.linux;
    mainProgram = "ppinfo";
  };
}
