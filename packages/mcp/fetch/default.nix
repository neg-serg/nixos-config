{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "mcp-server-fetch";
  version = "0.6.3";
  pyproject = true;
  src = ./src;

  nativeBuildInputs = [python3Packages.hatchling];
  propagatedBuildInputs = with python3Packages; [
    httpx
    markdownify
    mcp
    protego
    pydantic
    readabilipy
    requests
  ];

  pythonImportsCheck = ["mcp_server_fetch"];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace 'httpx<0.28' 'httpx<0.29'
  '';

  meta = with lib; {
    description = "MCP server for fetching/converting web content";
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "mcp-server-fetch";
  };
}
