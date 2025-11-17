{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "github-mcp";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "github";
    repo = "github-mcp-server";
    rev = "e9033462e13376e1a68422d492911972ec93d6a4";
    hash = "sha256-srLUNOSZMWl8ux1w5AJrHKXTHYUv+rn09+7X7IuwGwM=";
  };

  vendorHash = "sha256-j0THkLxOcNTyUoyl3WkbjR+8urM4fmsg7Mt74S4wjqU=";
  subPackages = ["cmd/github-mcp-server"];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "GitHub MCP server";
    homepage = "https://github.com/github/github-mcp-server";
    license = licenses.mit;
    mainProgram = "github-mcp-server";
    platforms = platforms.unix;
  };
}
