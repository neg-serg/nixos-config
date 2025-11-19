{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "postgres-mcp";
  version = "0.6.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@modelcontextprotocol/server-postgres/-/server-postgres-${version}.tgz";
    hash = "sha256-r1UgCgGxOuMZSftKiGTuYEO4kdAP+DMw0XebGKpbom8=";
  };

  npmDepsHash = "sha256-o8WyCsMt6Us8fKRe4KMXTOBlBkQGuMl/a+mc3RoLq7o=";

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "PostgreSQL MCP server";
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = licenses.mit;
    mainProgram = "mcp-server-postgres";
    platforms = platforms.unix;
    maintainers = [];
  };
}
