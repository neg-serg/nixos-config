{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "mcp-server-time";
  version = "0.6.2";
  pyproject = true;
  src = ./src;

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = with python3Packages; [
    mcp
    pydantic
    tzdata
    tzlocal
  ];

  pythonImportsCheck = ["mcp_server_time"];

  meta = with lib; {
    description = "MCP server providing time/timezone tools";
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "mcp-server-time";
  };
}
