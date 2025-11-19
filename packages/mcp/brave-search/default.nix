{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "brave-search-mcp";
  version = "2.0.59";

  src = fetchFromGitHub {
    owner = "brave";
    repo = "brave-search-mcp-server";
    rev = "v${version}";
    hash = "sha256-CPa4S3SHA+FcgfPaFYLK5DgWw/2vOAeCdE//7duHh9Y=";
  };

  npmDepsHash = "sha256-xufIkmEzWWquWc7scItQPnpNigILmzrjZXWZQA+adII=";

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "Brave Search MCP server";
    homepage = "https://github.com/brave/brave-search-mcp-server";
    license = licenses.mit;
    mainProgram = "brave-search-mcp-server";
    platforms = platforms.unix;
    maintainers = [];
  };
}
