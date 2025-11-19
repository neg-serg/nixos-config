{
  lib,
  python3Packages,
  fetchFromGitHub,
}: let
  inherit (python3Packages) buildPythonApplication hatchling mcp pydantic;
in
  buildPythonApplication rec {
    pname = "mcp-server-sqlite";
    version = "0.6.2";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "servers-archived";
      rev = "9be4674d1ddf8c469e6461a27a337eeb65f76c2e";
      hash = "sha256-GD0MIgh+vxI65vUb8UKWn5eD970ICbi2Mnr26O3+fRk=";
    };
    sourceRoot = "source/src/sqlite";

    nativeBuildInputs = [hatchling];
    propagatedBuildInputs = [mcp pydantic];

    pythonImportsCheck = ["mcp_server_sqlite"];

    meta = with lib; {
      description = "SQLite MCP server";
      homepage = "https://github.com/modelcontextprotocol/servers-archived";
      license = licenses.mit;
      mainProgram = "mcp-server-sqlite";
      platforms = platforms.unix;
    };
  }
