{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "firecrawl-mcp";
  version = "3.2.1";

  src = fetchFromGitHub {
    owner = "firecrawl";
    repo = "firecrawl-mcp-server";
    rev = "v${version}";
    hash = "sha256-RLcHZrQCdTOtOjv6u2df45pfthiD9BlyMqcZeH32C80=";
  };

  npmDepsHash = "sha256-6/IyDfjFyExuJDKtnYjHZxYoESjS9/rMbK/z7JthlVo=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "Firecrawl MCP server for search and crawling";
    homepage = "https://github.com/firecrawl/firecrawl-mcp-server";
    license = licenses.mit;
    mainProgram = "firecrawl-mcp";
    platforms = platforms.unix;
  };
}
