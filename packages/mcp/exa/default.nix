{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "exa-mcp";
  version = "3.0.9";

  src = fetchurl {
    url = "https://registry.npmjs.org/exa-mcp-server/-/exa-mcp-server-${version}.tgz";
    hash = "sha256-W8BBSihG58FuIJkzlNBSzn+BY0HburQYeCsG6mlqoEI=";
  };

  npmDepsHash = "sha256-3Yj81f8p8RdiSbP0Bon5UYg6Fz/GBWBM5XHGfNEDEKQ=";

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "Exa web + code search MCP server";
    homepage = "https://github.com/exa-labs/exa-mcp-server";
    license = licenses.mit;
    mainProgram = "exa-mcp-server";
    platforms = platforms.unix;
    maintainers = [];
  };
}
