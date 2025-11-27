{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "mcp-server-git";
  version = "0.6.2";
  pyproject = true;

  src = python3Packages.fetchPypi {
    pname = "mcp_server_git";
    inherit version;
    hash = "sha256-Rf7Ooi3qKSJFr9qR2GEIcjOEqYEtE5jmcGvx6q796uA=";
  };

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = with python3Packages; [
    click
    gitpython
    mcp
    pydantic
  ];

  pythonImportsCheck = ["mcp_server_git"];

  meta = with lib; {
    description = "MCP server exposing Git operations";
    homepage = "https://pypi.org/project/mcp-server-git/";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "mcp-server-git";
  };
}
