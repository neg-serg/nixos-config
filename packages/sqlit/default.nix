{
  lib,
  python3,
  inputs,
}:
let
  pyPkgs = python3.pkgs;
  version = "0.0.0+${inputs.sqlit.shortRev or "dirty"}";
in
pyPkgs.buildPythonApplication {
  pname = "sqlit";
  inherit version;
  pyproject = true;

  src = inputs.sqlit;

  build-system = [
    pyPkgs.hatchling
    pyPkgs.hatch-vcs
    pyPkgs.setuptools-scm
  ];

  nativeBuildInputs = [
    pyPkgs.pythonRelaxDepsHook
  ];

  pythonRelaxDeps = [
    "textual-fastdatatable"
  ];

  SETUPTOOLS_SCM_PRETEND_VERSION = version;

  dependencies = [
    pyPkgs.docker
    pyPkgs.keyring
    pyPkgs.pyperclip
    pyPkgs.sqlparse
    pyPkgs.textual
    pyPkgs.textual-fastdatatable
  ];

  pythonImportsCheck = [ "sqlit" ];

  meta = with lib; {
    description = "A terminal UI for SQL databases";
    homepage = "https://github.com/Maxteabag/sqlit";
    license = licenses.mit;
    mainProgram = "sqlit";
  };
}
