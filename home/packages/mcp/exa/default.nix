{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "exa-mcp";
  version = "3.0.9";

  src = fetchFromGitHub {
    owner = "exa-labs";
    repo = "exa-mcp-server";
    rev = "4862bf0181a7b38fcea70c7609ec8d8486f33037";
    hash = "sha256-jQQl8t96ju8u/E2qHwkQrbm5YxoksrUjQ8gYL4BJSMk=";
  };

  npmDepsHash = "sha256-3Yj81f8p8RdiSbP0Bon5UYg6Fz/GBWBM5XHGfNEDEKQ=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build:stdio",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = npmFlags;

  meta = with lib; {
    description = "Exa web search MCP server";
    homepage = "https://github.com/exa-labs/exa-mcp-server";
    license = licenses.mit;
    mainProgram = "exa-mcp-server";
    platforms = platforms.unix;
  };
}
