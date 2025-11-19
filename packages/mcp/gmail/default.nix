{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "gmail-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "PaulFidika";
    repo = "gmail-mcp-server";
    rev = "539a6fa810b0b0ccfd4ea7ce335694725cb4c98f";
    hash = "sha256-JK4m5FG70wXXnJzLrY9hFiwWOzDkkteIu61A/0zTKKQ=";
  };

  patches = [./refresh-token.patch];

  vendorHash = "sha256-FCtOVnwo2lNcL2LFuMJLe9kAj/raeAtu5lM22LjY1CM=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Gmail MCP server with OAuth (env + interactive support)";
    homepage = "https://github.com/PaulFidika/gmail-mcp-server";
    license = licenses.mit;
    mainProgram = "gmail-mcp-server";
    platforms = platforms.unix;
  };
}
