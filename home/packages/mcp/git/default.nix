{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "mcp-server-git";
  version = "0.6.2";
  pyproject = true;
  src = ./src;

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
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "mcp-server-git";
  };
}
