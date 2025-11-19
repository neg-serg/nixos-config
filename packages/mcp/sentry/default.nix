{
  lib,
  python3Packages,
  fetchFromGitHub,
}: let
  inherit (python3Packages) buildPythonApplication hatchling click httpx mcp;
in
  buildPythonApplication rec {
    pname = "mcp-server-sentry";
    version = "0.6.2";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "servers-archived";
      rev = "9be4674d1ddf8c469e6461a27a337eeb65f76c2e";
      hash = "sha256-GD0MIgh+vxI65vUb8UKWn5eD970ICbi2Mnr26O3+fRk=";
    };
    sourceRoot = "source/src/sentry";

    nativeBuildInputs = [hatchling];
    propagatedBuildInputs = [mcp httpx click];

    pythonImportsCheck = ["mcp_server_sentry"];

    meta = with lib; {
      description = "Sentry MCP server";
      homepage = "https://github.com/modelcontextprotocol/servers-archived";
      license = licenses.mit;
      mainProgram = "mcp-server-sentry";
      platforms = platforms.unix;
    };
  }
