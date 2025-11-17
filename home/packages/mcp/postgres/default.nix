{
  lib,
  buildNpmPackage,
}:
buildNpmPackage rec {
  pname = "postgres-mcp";
  version = "0.6.2";

  src = ./src;

  npmDepsHash = "sha256-o8WyCsMt6Us8fKRe4KMXTOBlBkQGuMl/a+mc3RoLq7o=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build",' ""
  '';

  meta = with lib; {
    description = "PostgreSQL MCP server";
    homepage = "https://github.com/modelcontextprotocol/servers-archived";
    license = licenses.mit;
    mainProgram = "mcp-server-postgres";
    platforms = platforms.unix;
  };
}
