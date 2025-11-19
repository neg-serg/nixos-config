{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "tsgram-mcp";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "areweai";
    repo = "tsgram-mcp";
    rev = "ff2778737d2b80b9ffeb5f4c5c7ae4555f458f44";
    hash = "sha256-J1yyKMtjprwZhJVnkWJ2mDjOFjyckPIOgVoi1qCwDKY=";
  };

  npmDepsHash = "sha256-W5Ipat325RivBYWsMRg0SHIJJ/nhZEf+Sx3VW0nX1ns=";

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;
  npmBuildScript = "build:mcp";

  meta = with lib; {
    description = "TSGram MCP server bridging Telegram bots";
    homepage = "https://github.com/areweai/tsgram-mcp";
    license = licenses.mit;
    mainProgram = "telegram-mcp";
    platforms = platforms.unix;
    maintainers = [];
  };
}
