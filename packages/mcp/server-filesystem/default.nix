{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "mcp-server-filesystem";
  version = "2025.8.21";

  src = fetchurl {
    url = "https://registry.npmjs.org/@modelcontextprotocol/server-filesystem/-/server-filesystem-${version}.tgz";
    hash = "sha256-voa3Gt1hb3HEd1dIkPL3KpcVmP20k+b0LxHQFwiLMz4=";
  };

  npmDepsHash = "sha256-v5T9cHqJuE4AfBTKXspLRsvqcX27skfGW6CItvmNn+Y=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace '"prepare": "npm run build",' ""
  '';

  npmFlags = ["--ignore-scripts"];
  npmInstallFlags = ["--ignore-scripts"];
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  meta = with lib; {
    description = "MCP server that exposes local filesystem access";
    homepage = "https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem";
    license = licenses.mit;
    mainProgram = "mcp-server-filesystem";
    platforms = platforms.unix;
    maintainers = [];
  };
}
